/* ================================================================
   2026-10-06: Bank Recon summary view (one row per batch)
   ================================================================
   New read-only proc for the second display of AccountingDevEx/BankReconFormV2
   (the "Summary" view; the grouped detail view stays, users switch between them).

   User rules (2026-10-06):
     * No Kind grouping, no expandable details.
     * Deposits in transit: one row per Control No, amount in Debit.
     * Outstanding checks:  one row per CV #,       amount in Credit.
     * An item with no Control No (DIT) / no CV # (OC) is its own row.
     * All batches are listed, with a status: CLEARED / PARTLY CLEARED / OPEN.
     * Staff clear by row: OpenReconIDs lists the batch's uncleared items, which
       the form sends to the existing sp_BankRecon_BulkResolveItems.

   The item rows are exactly those of sp_BankRecon_GetPeriod's DIT and OC result
   sets (same joins, same ControlNo / CV # derivation, reversed / voided items
   left out, every period up to @PeriodEnd). KEEP THE TWO IN STEP: a change to
   one of those queries in sp_BankRecon_GetPeriod must be made here too.

   Read-only: no table, type or existing object changes. Run on DEV first.
   ================================================================ */

IF OBJECT_ID('dbo.sp_BankRecon_GetPeriodSummary', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_BankRecon_GetPeriodSummary', 'sp_BankRecon_GetPeriodSummary_OLD_10062026120000';
GO

CREATE PROCEDURE dbo.sp_BankRecon_GetPeriodSummary
    @BranchCode  CHAR(3),
    @AccountCode VARCHAR(20),
    @PeriodEnd   DATE
AS
/*
    One row per batch: DIT by Control No (Debit), OC by CV # (Credit); an item
    without a batch number is its own row. Columns:
      ItemType ('DIT' / 'OC'), Kind, BatchKey (unique per row), BatchNo,
      Items, ClearedItems, Status, FirstDate, LastDate, Payee, CheckNo, CRNo,
      ReferenceNo (single-item rows), Debit, Credit, OpenAmount, OpenReconIDs
      (comma list of the uncleared items' ReconID, for Bulk Resolve).
*/
BEGIN
    SET NOCOUNT ON;

    ;WITH DIT AS (   -- = sp_BankRecon_GetPeriod "DIT ROWS"
        SELECT
            BSR.ReconID,
            BSR.ItemDate,
            COALESCE(NULLIF(LTRIM(RTRIM(BSR.ControlNo)), ''), NULLIF(LTRIM(RTRIM(ph.ControlNo)), '')) AS ControlNo,
            NULLIF(LTRIM(RTRIM(ph.CRNo)), '') AS CRNo,
            BSR.ReferenceNo,
            BSR.Payee,
            BSR.Amount,
            BSR.IsResolved
        FROM dbo.BankStatementRecon AS BSR
        INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
        OUTER APPLY (SELECT TOP (1) p.ControlNo, p.CRNo, p.PaymentType
                     FROM dbo.PaymentHeader AS p
                     WHERE BSR.SourceModule = 'AR-PAYMENT' AND p.ReferenceNo = BSR.SourceRef
                     ORDER BY p.PaymentHeaderID DESC) AS ph
        WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
          AND BSR.ItemType = 'DIT'
          AND ISNULL(BSR.ResolvedReason, '') <> 'REVERSED' AND ISNULL(BSR.ResolvedReason, '') NOT LIKE 'VOIDED%'),
    OC AS (          -- = sp_BankRecon_GetPeriod "OC ROWS"
        SELECT
            BSR.ReconID,
            BSR.ItemDate,
            BSR.Payee,
            BSR.Amount,
            BSR.IsResolved,
            NULLIF(LTRIM(RTRIM(cv.CheckNo)), '') AS CheckNo,
            NULLIF(LTRIM(RTRIM(CASE WHEN cv.HasRow = 1 THEN COALESCE(NULLIF(LTRIM(RTRIM(cv.CVNo)), ''), cv.NotedBy)
                                    WHEN tv.HasRow = 1 THEN tv.ControlNo
                                    WHEN ca.HasRow = 1 THEN ca.ControlNo END)), '') AS CVNo,
            BSR.ReferenceNo
        FROM dbo.BankStatementRecon AS BSR
        INNER JOIN dbo.BankReconHeader AS H ON BSR.HeaderID = H.HeaderID
        OUTER APPLY (SELECT TOP (1) x.ControlNo, x.CheckNo, x.CVNo, x.NotedBy, 1 AS HasRow FROM dbo.CheckVoucher AS x
                     WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                     ORDER BY x.SequenceNumber DESC) AS cv
        OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.CashVoucher AS x
                     WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                     ORDER BY x.SequenceNumber DESC) AS ca
        OUTER APPLY (SELECT TOP (1) x.ControlNo, 1 AS HasRow FROM dbo.TelegraphicVoucher AS x
                     WHERE CAST(x.VoucherID AS VARCHAR(20)) = BSR.ReferenceNo AND CAST(x.ReferenceNumber AS VARCHAR(20)) = BSR.SourceRef
                     ORDER BY x.SequenceNumber DESC) AS tv
        WHERE H.BranchCode = @BranchCode AND H.AccountCode = @AccountCode AND H.PeriodEnd <= @PeriodEnd
          AND BSR.ItemType = 'OC'
          AND ISNULL(BSR.ResolvedReason, '') <> 'REVERSED' AND ISNULL(BSR.ResolvedReason, '') NOT LIKE 'VOIDED%'),
    Items AS (
        SELECT 'DIT' AS ItemType, ReconID, ItemDate, CAST(ISNULL(Amount, 0) AS DECIMAL(18,2)) AS Amount,
               CAST(ISNULL(IsResolved, 0) AS INT) AS Cleared, ControlNo AS BatchNo,
               CRNo, CAST(NULL AS VARCHAR(50)) AS CheckNo, Payee, ReferenceNo
        FROM DIT
        UNION ALL
        SELECT 'OC', ReconID, ItemDate, CAST(ISNULL(Amount, 0) AS DECIMAL(18,2)),
               CAST(ISNULL(IsResolved, 0) AS INT), CVNo,
               CAST(NULL AS VARCHAR(50)), CheckNo, Payee, ReferenceNo
        FROM OC),
    K AS (
        SELECT i.*,
               CASE WHEN i.BatchNo IS NULL THEN 'ID:' + CAST(i.ReconID AS VARCHAR(20)) ELSE 'NO:' + i.BatchNo END AS BatchKey
        FROM Items AS i)
    SELECT
        k.ItemType,
        CASE k.ItemType WHEN 'DIT' THEN 'Deposit in Transit' ELSE 'Outstanding Check' END AS Kind,
        k.BatchKey,
        MAX(k.BatchNo)                                                     AS BatchNo,
        COUNT(*)                                                           AS Items,
        SUM(k.Cleared)                                                     AS ClearedItems,
        CASE WHEN SUM(k.Cleared) = COUNT(*) THEN 'CLEARED'
             WHEN SUM(k.Cleared) > 0       THEN 'PARTLY CLEARED'
             ELSE 'OPEN' END                                               AS Status,
        MIN(k.ItemDate)                                                    AS FirstDate,
        MAX(k.ItemDate)                                                    AS LastDate,
        CASE WHEN COUNT(DISTINCT k.Payee) > 1 THEN '(several)' ELSE MAX(k.Payee) END             AS Payee,
        CASE WHEN COUNT(DISTINCT k.CheckNo) > 1 THEN '(several)' ELSE MAX(k.CheckNo) END         AS CheckNo,
        CASE WHEN COUNT(DISTINCT k.CRNo) > 1 THEN '(several)' ELSE MAX(k.CRNo) END               AS CRNo,
        CASE WHEN COUNT(*) = 1 THEN MAX(k.ReferenceNo) END                                       AS ReferenceNo,
        SUM(CASE WHEN k.ItemType = 'DIT' THEN k.Amount ELSE 0 END)                               AS Debit,
        SUM(CASE WHEN k.ItemType = 'OC'  THEN k.Amount ELSE 0 END)                               AS Credit,
        SUM(CASE WHEN k.Cleared = 0 THEN k.Amount ELSE 0 END)                                    AS OpenAmount,
        STRING_AGG(CASE WHEN k.Cleared = 0 THEN CAST(k.ReconID AS VARCHAR(MAX)) END, ',')
            WITHIN GROUP (ORDER BY k.ReconID)                                                     AS OpenReconIDs
    FROM K AS k
    GROUP BY k.ItemType, k.BatchKey
    ORDER BY CASE k.ItemType WHEN 'DIT' THEN 0 ELSE 1 END, MAX(k.ItemDate) DESC, k.BatchKey;
END
GO
