/* ================================================================
   2026-10-09b: reversals dated in the month of their source entry (data fix)
   ================================================================
   Data only, no object changes. Found on STAGING (restore of PRODUCTION
   2026-10-08), so the tickets / ReconIDs are production's.

   Finding (2026-10-09, sent to the accountants as
   docs/reports/2026-10-09_BankRecon_ReversedInLaterMonth_STAGING.xlsx):
   16 bank recon items (12 references) were posted in August (one in
   September) and reversed / voided in a LATER month. The recon hides a
   reversed item in every month, but the GL had the original entry in its
   own month and the reversal only in the next one, so that month could
   never reconcile.

   Accountants' answer (2026-10-09): the reversal falls into the month of
   the source entry, the same as the source entry.
   -> each reversal ticket (TicketMaster + all its TicketDetails lines, every
      account, so it stays balanced) gets the date of its source ticket;
   -> the reversal rows of the supplier / client ledger get the source row's
      TransactionDate (PostingDate = when it was entered, kept);
   -> the recon items are closed in the source month (ClearedPeriodEnd), and
      ReconID 38 (filed under September for an August cheque) moves to the
      August period.
   Nothing else changes: amounts, accounts, ticket numbers, statuses, the
   vouchers, payments and cash advances stay as they are.

   The 12 references (18 reversal tickets) are the verified list; a reference
   whose tickets differ from what was found stops the whole script.
   Refused when a GL month or a bank recon period that would change is closed.

   Backups (rows before the change):
     TicketMaster_RevDate_Backup_20261009, TicketDetails_RevDate_Backup_20261009,
     SupplierLedger_RevDate_Backup_20261009, ClientLedger_RevDate_Backup_20261009,
     BankStatementRecon_RevDate_Backup_20261009.
   The procedures are changed separately (reversals dated in the source month
   from now on): 2026-10-09c_Reversal_SourceMonthDate.sql.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @User VARCHAR(50) = 'REVDATE-FIX-20261009';

IF OBJECT_ID('dbo.TicketMaster_RevDate_Backup_20261009', 'U') IS NOT NULL
    THROW 93501, 'TicketMaster_RevDate_Backup_20261009 already exists: this script has been run here before.', 1;

-- the verified list: reference, ticket ReferenceKey, source date, number of reversal tickets
DECLARE @Refs TABLE (ReferenceNumber VARCHAR(20) PRIMARY KEY, ReferenceKey VARCHAR(50), SourceDate DATE, RevTickets INT);
INSERT INTO @Refs VALUES
    ('14107', '14107', '2026-08-01', 1),   -- AR payment, PNB PESO DIT 9,049.60
    ('19795', '628',   '2026-08-04', 1),   -- BDO PESO 2 cheque 100,255.99 (ReconID 38)
    ('26750', '666',   '2026-08-04', 1),   -- BDO PESO 1 cheque 36,270.70
    ('27019', '27019', '2026-08-05', 1),   -- transfer PNB PESO -> PNB PESO 2, 1,075,999.00
    ('28481', '685',   '2026-08-10', 2),   -- BDO PESO 1 cheque 14,734.50
    ('28772', '707',   '2026-08-13', 1),   -- BDO PESO 1 cheque 17,637.19
    ('32117', '736',   '2026-08-13', 1),   -- BDO PESO 1 cheque 17,637.19
    ('32424', '32424', '2026-08-14', 1),   -- BDO PESO 1 to itself, 500,000.00
    ('32509', '32509', '2026-08-14', 1),   -- transfer MBTC PESO 1 -> MBTC PESO 2, 1,256,904.23
    ('32873', '768',   '2026-08-14', 2),   -- BDO PESO 2 cheque 1,088,776.16
    ('32877', '769',   '2026-08-14', 5),   -- BDO PESO 2 cheque 5,914,761.28
    ('37271', '37271', '2026-09-08', 1);   -- transfer PNB PESO -> PNB PESO 2, 1,001,999.00 (September)

BEGIN TRANSACTION;

    -- the reversal tickets and their new date (= the source ticket's date)
    SELECT  tm.TicketNumber, tm.BranchCode, tm.ReferenceNumber, tm.ReferenceKey,
            CAST(tm.TicketDate AS DATE) AS OldDate, s.SourceDate AS NewDate
    INTO #Rev
    FROM dbo.TicketMaster AS tm WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN @Refs AS r ON r.ReferenceNumber = tm.ReferenceNumber AND r.ReferenceKey = tm.ReferenceKey
    CROSS APPLY (SELECT MIN(CAST(o.TicketDate AS DATE)) AS SourceDate
                 FROM dbo.TicketMaster AS o
                 WHERE o.ReferenceNumber = tm.ReferenceNumber AND o.ReferenceKey = tm.ReferenceKey
                   AND ISNULL(o.Product, '') NOT LIKE 'REVERSAL%') AS s
    WHERE tm.Product LIKE 'REVERSAL%';

    -- every reference exactly as found: its source date, its number of reversal tickets, all of them in a later month
    IF EXISTS (SELECT 1 FROM @Refs AS r
               OUTER APPLY (SELECT COUNT(*) AS n, MIN(v.NewDate) AS d1, MAX(v.NewDate) AS d2,
                                   SUM(CASE WHEN EOMONTH(v.OldDate) > EOMONTH(v.NewDate) THEN 1 ELSE 0 END) AS later
                            FROM #Rev AS v WHERE v.ReferenceNumber = r.ReferenceNumber) AS x
               WHERE x.n <> r.RevTickets OR x.d1 <> r.SourceDate OR x.d2 <> r.SourceDate OR x.later <> r.RevTickets)
        THROW 93502, 'At least one reference is not as found on 2026-10-09 (reversal tickets or dates differ); nothing changed.', 1;

    -- each reference is fully reversed on its bank accounts (nets to 0)
    IF EXISTS (SELECT 1 FROM dbo.TicketDetails AS td INNER JOIN @Refs AS r ON r.ReferenceNumber = td.ReferenceNumber AND r.ReferenceKey = td.ReferenceKey
               WHERE td.AccountCode LIKE '10102%'
               GROUP BY td.ReferenceNumber, td.AccountCode HAVING SUM(td.Debit - td.Credit) <> 0)
        THROW 93503, 'A reference does not net to 0 on its bank account; nothing changed.', 1;

    -- closed months: GL lock, or a locked bank recon period of a bank account involved, from the source month on
    IF EXISTS (SELECT 1 FROM dbo.GLPeriodLock AS l WITH (HOLDLOCK) CROSS JOIN #Rev AS v WHERE l.LockedThroughDate >= v.NewDate)
        THROW 93504, 'The GL month of a source entry is closed (GLPeriodLock); nothing changed.', 1;
    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h WITH (HOLDLOCK)
               WHERE h.Status = 'LOCKED'
                 AND EXISTS (SELECT 1 FROM dbo.TicketDetails AS td INNER JOIN #Rev AS v ON v.TicketNumber = td.TicketNumber AND v.BranchCode = td.BranchCode
                             WHERE td.AccountCode = h.AccountCode AND h.PeriodEnd >= EOMONTH(v.NewDate)))
        THROW 93505, 'A bank recon period that would change is LOCKED; nothing changed.', 1;

    DECLARE @AugBDO2 INT = (SELECT HeaderID FROM dbo.BankReconHeader WHERE BranchCode = '888' AND AccountCode = '101020102' AND PeriodEnd = '2026-08-31');
    IF @AugBDO2 IS NULL
        THROW 93506, 'The BDO PESO 2 August period (branch 888) was not found; nothing changed.', 1;

    -- backups
    SELECT tm.* INTO dbo.TicketMaster_RevDate_Backup_20261009
    FROM dbo.TicketMaster AS tm INNER JOIN #Rev AS v ON v.TicketNumber = tm.TicketNumber AND v.BranchCode = tm.BranchCode AND v.ReferenceNumber = tm.ReferenceNumber;

    SELECT td.* INTO dbo.TicketDetails_RevDate_Backup_20261009
    FROM dbo.TicketDetails AS td INNER JOIN #Rev AS v ON v.TicketNumber = td.TicketNumber AND v.BranchCode = td.BranchCode AND v.ReferenceNumber = td.ReferenceNumber;

    SELECT sl.* INTO dbo.SupplierLedger_RevDate_Backup_20261009
    FROM dbo.SupplierLedger AS sl INNER JOIN @Refs AS r ON r.ReferenceNumber = sl.ReferenceNumber
    WHERE sl.PaymentType = 'REVERSAL';

    SELECT cl.* INTO dbo.ClientLedger_RevDate_Backup_20261009
    FROM dbo.ClientLedger AS cl INNER JOIN #Rev AS v ON v.ReferenceNumber = cl.ReferenceNumber AND v.TicketNumber = cl.TicketReference;

    SELECT b.ReconID, b.HeaderID, b.PeriodEnd, b.ItemDate, b.ClearedPeriodEnd, b.UpdatedBy, b.DateTimeUpdated
    INTO dbo.BankStatementRecon_RevDate_Backup_20261009
    FROM dbo.BankStatementRecon AS b INNER JOIN @Refs AS r ON r.ReferenceNumber = b.SourceRef
    WHERE b.AccountCode LIKE '10102%' AND (b.ResolvedReason = 'REVERSED' OR b.ResolvedReason LIKE 'VOIDED%');

    -- 1. the reversal tickets take the source date (master + every line)
    UPDATE tm SET TicketDate = v.NewDate
    FROM dbo.TicketMaster AS tm INNER JOIN #Rev AS v ON v.TicketNumber = tm.TicketNumber AND v.BranchCode = tm.BranchCode AND v.ReferenceNumber = tm.ReferenceNumber;
    IF @@ROWCOUNT <> 18 THROW 93507, 'Step 1 did not re-date exactly 18 ticket masters.', 1;

    UPDATE td SET TicketDate = v.NewDate
    FROM dbo.TicketDetails AS td INNER JOIN #Rev AS v ON v.TicketNumber = td.TicketNumber AND v.BranchCode = td.BranchCode AND v.ReferenceNumber = td.ReferenceNumber;
    DECLARE @Lines INT = @@ROWCOUNT;

    -- 2. supplier ledger reversal rows: the TransactionDate of the row they reverse
    UPDATE sl SET TransactionDate = o.TransactionDate
    FROM dbo.SupplierLedger AS sl
    INNER JOIN @Refs AS r ON r.ReferenceNumber = sl.ReferenceNumber
    CROSS APPLY (SELECT TOP (1) x.TransactionDate FROM dbo.SupplierLedger AS x
                 WHERE x.SupplierID = sl.SupplierID AND x.ReferenceNumber = sl.ReferenceNumber
                   AND x.TicketReference = sl.TicketReference AND x.PaymentType <> 'REVERSAL'
                 ORDER BY x.TRN_SEQ_NO) AS o
    WHERE sl.PaymentType = 'REVERSAL' AND CAST(sl.TransactionDate AS DATE) <> CAST(o.TransactionDate AS DATE);
    DECLARE @SL INT = @@ROWCOUNT;

    -- 3. client ledger reversal rows (AR payment 14107): the source date
    UPDATE cl SET TransactionDate = v.NewDate
    FROM dbo.ClientLedger AS cl INNER JOIN #Rev AS v ON v.ReferenceNumber = cl.ReferenceNumber AND v.TicketNumber = cl.TicketReference
    WHERE CAST(cl.TransactionDate AS DATE) <> v.NewDate;
    DECLARE @CL INT = @@ROWCOUNT;

    -- 4. recon items: closed in the source month; ReconID 38 into the August period
    UPDATE b
    SET     ClearedPeriodEnd = EOMONTH(r.SourceDate),
            HeaderID         = CASE WHEN b.ReconID = 38 THEN @AugBDO2 ELSE b.HeaderID END,
            PeriodEnd        = CASE WHEN b.ReconID = 38 THEN '2026-08-31' ELSE b.PeriodEnd END,
            ItemDate         = CASE WHEN b.ReconID = 38 THEN r.SourceDate ELSE b.ItemDate END,
            UpdatedBy        = @User,
            DateTimeUpdated  = GETDATE()
    FROM dbo.BankStatementRecon AS b INNER JOIN @Refs AS r ON r.ReferenceNumber = b.SourceRef
    WHERE b.AccountCode LIKE '10102%' AND (b.ResolvedReason = 'REVERSED' OR b.ResolvedReason LIKE 'VOIDED%');
    DECLARE @BR INT = @@ROWCOUNT;
    IF @BR <> 16 THROW 93508, 'Step 4 did not touch exactly the 16 recon items.', 1;

    -- post-checks
    IF EXISTS (SELECT 1 FROM dbo.TicketDetails AS td INNER JOIN #Rev AS v ON v.TicketNumber = td.TicketNumber AND v.BranchCode = td.BranchCode
               GROUP BY td.TicketNumber, td.BranchCode HAVING SUM(td.Debit) <> SUM(td.Credit) OR COUNT(DISTINCT CAST(td.TicketDate AS DATE)) <> 1)
        THROW 93509, 'Post-check: a re-dated ticket does not balance or has lines on two dates; nothing changed.', 1;

    -- each reference nets to 0 on its bank account by the end of the source month
    IF EXISTS (SELECT 1 FROM dbo.TicketDetails AS td INNER JOIN @Refs AS r ON r.ReferenceNumber = td.ReferenceNumber AND r.ReferenceKey = td.ReferenceKey
               WHERE td.AccountCode LIKE '10102%' AND td.TicketDate < DATEADD(DAY, 1, EOMONTH(r.SourceDate))
               GROUP BY td.ReferenceNumber, td.AccountCode HAVING SUM(td.Debit - td.Credit) <> 0)
        THROW 93510, 'Post-check: a reference does not net to 0 by the end of its source month; nothing changed.', 1;

    -- nothing reversed in a later month is left (same test as the BRC-REVERSED-LATER-MONTH check)
    IF EXISTS (
        SELECT 1
        FROM dbo.BankStatementRecon AS b
        LEFT JOIN dbo.BankReconHeader AS h ON h.HeaderID = b.HeaderID
        CROSS APPLY (SELECT MIN(CAST(td.TicketDate AS DATE)) AS FirstDate, MAX(CAST(td.TicketDate AS DATE)) AS LastDate
                     FROM dbo.TicketDetails AS td WHERE td.AccountCode = b.AccountCode AND td.ReferenceNumber = b.SourceRef) AS g
        INNER JOIN @Refs AS r ON r.ReferenceNumber = b.SourceRef
        WHERE b.AccountCode LIKE '10102%' AND (b.ResolvedReason = 'REVERSED' OR b.ResolvedReason LIKE 'VOIDED%')
          AND (EOMONTH(g.FirstDate) <> EOMONTH(g.LastDate) OR h.PeriodEnd > EOMONTH(g.FirstDate)))
        THROW 93511, 'Post-check: an item is still reversed in a later month; nothing changed.', 1;

COMMIT TRANSACTION;

-- Result
SELECT  v.ReferenceNumber, v.TicketNumber, v.BranchCode,
        CONVERT(VARCHAR(10), v.OldDate, 120) AS WasDated, CONVERT(VARCHAR(10), v.NewDate, 120) AS NowDated,
        (SELECT SUM(td.Debit) FROM dbo.TicketDetails AS td WHERE td.TicketNumber = v.TicketNumber AND td.BranchCode = v.BranchCode) AS TicketAmount
FROM #Rev AS v
ORDER BY v.NewDate, v.ReferenceNumber, v.TicketNumber;

SELECT @Lines AS TicketLines, @SL AS SupplierLedgerRows, @CL AS ClientLedgerRows, @BR AS ReconItems;
