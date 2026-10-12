/* ================================================================
   2026-10-08: Bank Recon data fix (3 findings of the GL-vs-recon check)
   ================================================================
   Data only, no object changes. Touches BankStatementRecon only (14 rows);
   tickets, GL, vouchers, payments and cash advances are not changed.
   Found on STAGING after the 2026-10-08 restore of PRODUCTION, so the
   ReconIDs are production's. Every row is checked against the values it
   was found with; if any row differs (cleared, edited, moved), nothing
   is changed.

   1. Duplicate fund transfer BDO PESO 1 -> BDO PESO 2, 1,294,034.25, 2026-08-12.
      Two cash advances exist for it: voucher 627 / ref 13157 and voucher
      694 / ref 28522 (same payee, amount, date). Only 28522 is in the GL
      (ticket 12884). The recon has both pairs, so BDO PESO 1 carried an
      extra outstanding check and BDO PESO 2 an extra deposit in transit.
      -> ReconID 22 (OC) and 23 (DIT) are voided, like a reversed payment.
      Cash advance 133 (ref 13157) itself is left for the accountant.

   2. BDO PESO 2: 11 supplier cheques (vouchers 629-638, 641; 2,469,007.48)
      are dated 2026-08-04 .. 08-19 in the GL, but their OC rows were created
      on 09-14 / 09-15, dated 09-14 and filed under the September period, so
      August did not list them as outstanding.
      -> moved to the August 31 period, ItemDate = the GL date.

   3. MBTC PESO 2: Manual JV 32412 (ticket 19283, 2026-08-31) credits the bank
      on 6 lines (383,499.06); only the first line (3,746.25) got an OC
      (Known Bug Pattern #9: the recon helper is idempotent per reference,
      account and type). User rule 2026-10-08: one item per JV.
      -> the OC amount becomes the JV's total bank credit, 383,499.06.
      The procedure is fixed separately: 2026-10-08b_JV_BankRecon_OneItemPerAccount.sql.

   Backup: BankStatementRecon_Fix_Backup_20261008 (the 14 rows before the change).
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @User VARCHAR(50) = 'BANKRECON-FIX-20261008';

IF OBJECT_ID('dbo.BankStatementRecon_Fix_Backup_20261008', 'U') IS NOT NULL
    THROW 93401, 'BankStatementRecon_Fix_Backup_20261008 already exists: this script has been run here before.', 1;

DECLARE @AugBDO2 INT = (SELECT HeaderID FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = '101020102' AND PeriodEnd = '2026-08-31');
DECLARE @SepBDO2 INT = (SELECT HeaderID FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = '101020102' AND PeriodEnd = '2026-09-30');
IF @AugBDO2 IS NULL OR @SepBDO2 IS NULL
    THROW 93402, 'The BDO PESO 2 August / September recon periods (branch 888) were not found.', 1;

-- sp-reviewer 2026-10-08: never change a locked period's figures (BDO PESO 1 / 2, MBTC PESO 2, August on)
IF EXISTS (SELECT 1 FROM dbo.BankReconHeader
           WHERE AccountCode IN ('101020101', '101020102', '101020108') AND PeriodEnd >= '2026-08-31' AND Status = 'LOCKED')
    THROW 93411, 'A recon period of BDO PESO 1 / BDO PESO 2 / MBTC PESO 2 from August on is LOCKED; nothing changed.', 1;

-- the rows, exactly as found on 2026-10-08
DECLARE @Expect TABLE (ReconID INT PRIMARY KEY, Fix TINYINT, AccountCode VARCHAR(20), ItemType VARCHAR(5), SourceRef VARCHAR(50), Amount DECIMAL(18,2));
INSERT INTO @Expect VALUES
    (22, 1, '101020101', 'OC',  '13157', 1294034.25),
    (23, 1, '101020102', 'DIT', '13157', 1294034.25),
    (39, 2, '101020102', 'OC',  '19849',  468055.33),
    (40, 2, '101020102', 'OC',  '19998',  197960.60),
    (41, 2, '101020102', 'OC',  '20018',   86022.35),
    (42, 2, '101020102', 'OC',  '20025',   96958.52),
    (43, 2, '101020102', 'OC',  '20032',  242545.80),
    (44, 2, '101020102', 'OC',  '20039',  179976.07),
    (45, 2, '101020102', 'OC',  '20044',  832055.37),
    (46, 2, '101020102', 'OC',  '20050',   96921.04),
    (47, 2, '101020102', 'OC',  '20055',   88534.89),
    (48, 2, '101020102', 'OC',  '20058',   79721.52),
    (82, 2, '101020102', 'OC',  '20989',  100255.99),
    (5467, 3, '101020108', 'OC', '32412',    3746.25);

BEGIN TRANSACTION;

    -- every row must still be as found: same account / type / reference / amount, uncleared
    IF (SELECT COUNT(*)
        FROM dbo.BankStatementRecon AS b WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
        WHERE b.AccountCode = e.AccountCode AND b.ItemType = e.ItemType AND b.SourceRef = e.SourceRef
          AND b.Amount = e.Amount AND ISNULL(b.IsResolved, 0) = 0
          AND (e.Fix <> 2 OR b.HeaderID = @SepBDO2)) <> 14
        THROW 93403, 'At least one of the 14 rows has changed since 2026-10-08 (cleared, edited or moved); nothing changed.', 1;

    -- fix 1 only if the real transfer (ref 28522) is there and ref 13157 never reached the bank accounts in the GL
    IF NOT EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE ReferenceNumber = '28522' AND AccountCode = '101020101' AND Credit = 1294034.25)
       OR NOT EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE ReferenceNumber = '28522' AND AccountCode = '101020102' AND Debit = 1294034.25)
       OR EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE ReferenceNumber = '13157' AND AccountCode IN ('101020101', '101020102'))
        THROW 93404, 'The fund transfer is not as found (ref 28522 missing, or ref 13157 has bank lines); nothing changed.', 1;

    -- fix 3: the JV's bank credit total from the GL
    DECLARE @JVTotal DECIMAL(18,2) = (SELECT SUM(Credit) - SUM(Debit) FROM dbo.TicketDetails WHERE ReferenceNumber = '32412' AND AccountCode = '101020108');
    IF @JVTotal IS NULL OR @JVTotal <> 383499.06
        THROW 93405, 'Manual JV 32412 bank credit total is not 383,499.06; nothing changed.', 1;

    SELECT b.* INTO dbo.BankStatementRecon_Fix_Backup_20261008
    FROM dbo.BankStatementRecon AS b INNER JOIN @Expect AS e ON e.ReconID = b.ReconID;

    -- 1. void the duplicate pair
    UPDATE b
    SET     IsResolved      = 1,
            ResolvedDate    = GETDATE(),
            ResolvedBy      = @User,
            ResolvedReason  = 'VOIDED - DUPLICATE OF CASH ADVANCE 694 / REF 28522',
            UpdatedBy       = @User,
            DateTimeUpdated = GETDATE()
    FROM dbo.BankStatementRecon AS b INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
    WHERE e.Fix = 1;
    IF @@ROWCOUNT <> 2 THROW 93406, 'Fix 1 did not touch exactly 2 rows.', 1;

    -- 2. the 11 August cheques into the August period, dated with their GL date
    UPDATE b
    SET     HeaderID        = @AugBDO2,
            PeriodEnd       = '2026-08-31',
            ItemDate        = g.GLDate,
            UpdatedBy       = @User,
            DateTimeUpdated = GETDATE()
    FROM dbo.BankStatementRecon AS b
    INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
    CROSS APPLY (SELECT MIN(CAST(td.TicketDate AS DATE)) AS GLDate
                 FROM dbo.TicketDetails AS td
                 WHERE td.AccountCode = b.AccountCode AND td.ReferenceNumber = b.SourceRef) AS g
    WHERE e.Fix = 2 AND g.GLDate >= '2026-08-01' AND g.GLDate <= '2026-08-31';
    IF @@ROWCOUNT <> 11 THROW 93407, 'Fix 2 did not move exactly 11 rows (a GL date is outside August).', 1;

    -- 3. one item per JV: the full bank credit
    UPDATE b
    SET     Amount          = @JVTotal,
            Remarks         = LEFT(ISNULL(b.Remarks, '') + ' | all 6 bank lines (was 3,746.25, first line only)', 500),
            UpdatedBy       = @User,
            DateTimeUpdated = GETDATE()
    FROM dbo.BankStatementRecon AS b INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
    WHERE e.Fix = 3;
    IF @@ROWCOUNT <> 1 THROW 93408, 'Fix 3 did not touch exactly 1 row.', 1;

    -- post-check: for the references involved, GL net = recon net (DIT +, OC -, voided = 0) per account
    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT AccountCode, SourceRef FROM @Expect WHERE SourceRef <> '13157'
              UNION SELECT '101020101', '28522' UNION SELECT '101020102', '28522') AS k
        OUTER APPLY (SELECT ISNULL(SUM(td.Debit - td.Credit), 0) AS GLNet FROM dbo.TicketDetails AS td
                     WHERE td.AccountCode = k.AccountCode AND td.ReferenceNumber = k.SourceRef AND td.TicketDate >= '2026-08-01') AS g
        OUTER APPLY (SELECT ISNULL(SUM(CASE WHEN ISNULL(b.ResolvedReason, '') = 'REVERSED' OR ISNULL(b.ResolvedReason, '') LIKE 'VOIDED%' THEN 0
                                            WHEN b.ItemType = 'DIT' THEN b.Amount ELSE -b.Amount END), 0) AS RecNet
                     FROM dbo.BankStatementRecon AS b WHERE b.AccountCode = k.AccountCode AND b.SourceRef = k.SourceRef AND b.ItemType IN ('DIT', 'OC')) AS r
        WHERE g.GLNet <> r.RecNet)
        THROW 93409, 'Post-check: GL and recon still differ for one of the references; nothing changed.', 1;

    IF EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
               WHERE e.SourceRef = '13157' AND (ISNULL(b.IsResolved, 0) = 0 OR b.ResolvedReason NOT LIKE 'VOIDED%'))
        THROW 93410, 'Post-check: the duplicate pair is not voided; nothing changed.', 1;

COMMIT TRANSACTION;

-- Result
SELECT b.ReconID, b.AccountCode, b.ItemType, b.SourceRef, b.Amount, CONVERT(VARCHAR(10), b.ItemDate, 120) AS ItemDate,
       CONVERT(VARCHAR(10), h.PeriodEnd, 120) AS Period, b.IsResolved, b.ResolvedReason
FROM dbo.BankStatementRecon AS b
INNER JOIN @Expect AS e ON e.ReconID = b.ReconID
LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
ORDER BY e.Fix, b.ReconID;

SELECT h.AccountCode, CONVERT(VARCHAR(10), h.PeriodEnd, 120) AS PeriodEnd, f.OpenDIT, f.OpenOC, f.Difference
FROM dbo.BankReconHeader AS h CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
WHERE h.BranchCode = '888' AND h.AccountCode IN ('101020101', '101020102', '101020108')
ORDER BY h.AccountCode, h.PeriodEnd;
