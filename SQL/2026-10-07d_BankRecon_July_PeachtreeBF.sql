/* ================================================================
   2026-10-07d: Bank Recon balance forward from Peachtree (July 2026)
   ================================================================
   One-time data load, no object changes. Source: the accountant's July
   Peachtree reconciliation workbook (5 sheets, one per bank account).
   The system's GL starts with the opening ticket of 2026-07-31, so the
   items that were still uncleared in Peachtree on 2026-07-31 have to be
   loaded once as reconciling items of a July 31 recon period. From there
   they carry forward into August (open items = uncleared items of every
   header with PeriodEnd <= the selected one) until they are cleared.

   Per account (branch 888, the branch every recon file is under):
     * July 31 header: created if missing; BankStatementBal = Peachtree
       "Ending Bank Balance"; GLBookBalance = fn_BankRecon_GLBalance.
     * Deposits in transit  -> ItemType DIT
     * Outstanding checks   -> ItemType OC   (ReferenceNo = "CV no. / check no.")
     * "Add (Less) Other" (Peachtree GJ entries not yet on the bank):
         positive -> DIT, negative -> OC  (same sign on the bank side)
     All rows: SourceModule 'BF-PEACHTREE', original Peachtree date,
     Amount positive, IsResolved = 0, ControlNo = the Peachtree reference.

   Sheet -> account:
     BDO PESO 1 -> 101020101   BDO PESO 2 -> 101020102   WB -> 101020104
     MBTC 1-1   -> 101020107   MBTC 2     -> 101020108

   Left out on purpose:
     BDO PESO 2 OC X2607-067 / BDO2246143, 15,898.47 (2026-07-31).
       The system's July 31 GL (7,405,929.09) is 15,898.47 above the
       sheet's (7,390,030.62): the opening ticket does not include this
       check. A check the books don't have can't be outstanding in them.
       If it was issued, book it in the system (Manual JV, CR the bank);
       that posting creates its own OC row.

   Expected July 31 difference (Adjusted Bank - Adjusted Book) after the load:
     101020101 0.00          101020107 0.00        101020108 0.00
     101020102 -1,978,452.67 101020104 -1,000,050.00
   The last two are Peachtree's own unreconciled differences (the sheet
   shows them as +1,978,452.67 / +1,000,050.00, book - bank); the
   accountant has to explain them. The post-check refuses anything else.

   Re-runnable: rows already loaded (same account + SourceModule +
   ReferenceNo) are skipped; a LOCKED July header stops the script.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PeriodEnd DATE = '2026-07-31', @Branch CHAR(3) = '888', @User VARCHAR(50) = 'BF-PEACHTREE';

DECLARE @Acct TABLE (AccountCode VARCHAR(20) PRIMARY KEY, Sheet VARCHAR(20), BankBal DECIMAL(18,2), ExpectedDiff DECIMAL(18,2));
INSERT INTO @Acct VALUES
    ('101020101', 'BDO PESO 1', 3703850.09,           0.00),
    ('101020102', 'BDO PESO 2', 7484719.57,   -1978452.67),
    ('101020104', 'WB',          785223.68,   -1000050.00),
    ('101020107', 'MBTC 1-1',   4881448.93,           0.00),
    ('101020108', 'MBTC 2',     4650438.38,           0.00);

DECLARE @Item TABLE (AccountCode VARCHAR(20), ItemType VARCHAR(5), ItemDate DATE, PeachtreeRef VARCHAR(50),
                     ReferenceNo VARCHAR(150), Amount DECIMAL(18,2), Section VARCHAR(30));
INSERT INTO @Item VALUES
    -- BDO PESO 1
    ('101020101', 'DIT', '2026-07-31', 'N2607-31-A',           'N2607-31-A',               92178.55, 'Deposit in transit'),
    ('101020101', 'OC',  '2026-04-30', 'CV2604-139BDO2384165', 'CV2604-139 / BDO2384165', 400000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-06-12', 'CV2606-052BDO2384302', 'CV2606-052 / BDO2384302', 400000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-06-12', 'CV2606-053BDO2384303', 'CV2606-053 / BDO2384303', 550000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-06-12', 'CV2606-054BDO2384304', 'CV2606-054 / BDO2384304', 550000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-07-13', 'CV2607-086BDO2384410', 'CV2607-086 / BDO2384410',3382485.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-07-24', 'CV2607-140BDO2384437', 'CV2607-140 / BDO2384437', 300000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-07-24', 'CV2607-141BDO2384438', 'CV2607-141 / BDO2384438', 300000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-07-31', 'CV2607-190BDO2384459', 'CV2607-190 / BDO2384459', 100000.00, 'Outstanding check'),
    ('101020101', 'OC',  '2026-07-31', 'CV2607-191BDO2384460', 'CV2607-191 / BDO2384460',1350000.00, 'Outstanding check'),
    ('101020101', 'DIT', '2026-07-31', 'GJ 2607-052',          'GJ 2607-052',                 212.00, 'Add (Less) Other'),
    ('101020101', 'DIT', '2026-07-31', 'GJ 2607-053',          'GJ 2607-053',               16151.08, 'Add (Less) Other'),
    -- BDO PESO 2 (X2607-067 left out, see the header)
    ('101020102', 'DIT', '2026-07-31', 'A2607-31-A',           'A2607-31-A',              488370.09, 'Deposit in transit'),
    ('101020102', 'OC',  '2026-03-23', 'X2603-074BDO2245894',  'X2603-074 / BDO2245894',    5851.23, 'Outstanding check'),
    ('101020102', 'OC',  '2026-05-22', 'X2605-071BDO2246022',  'X2605-071 / BDO2246022',   28049.11, 'Outstanding check'),
    ('101020102', 'OC',  '2026-06-29', 'X2606-046BDO2246088',  'X2606-046 / BDO2246088',  356930.00, 'Outstanding check'),
    ('101020102', 'OC',  '2026-07-09', 'X2607-014BDO2246110',  'X2607-014 / BDO2246110',    7373.57, 'Outstanding check'),
    ('101020102', 'OC',  '2026-07-21', 'X2607-042BDO2246130',  'X2607-042 / BDO2246130',  770368.58, 'Outstanding check'),
    ('101020102', 'OC',  '2026-07-21', 'X2607-046BDO2246134',  'X2607-046 / BDO2246134',   55000.00, 'Outstanding check'),
    ('101020102', 'OC',  '2026-07-21', 'X2607-047BDO2246135',  'X2607-047 / BDO2246135',  121470.92, 'Outstanding check'),
    ('101020102', 'OC',  '2026-07-21', 'X2607-050BDO2246138',  'X2607-050 / BDO2246138', 1200569.83, 'Outstanding check'),
    -- MBTC 1-1
    ('101020107', 'DIT', '2026-07-28', 'K2607-28-A',           'K2607-28-A',              133786.30, 'Deposit in transit'),
    ('101020107', 'DIT', '2026-07-29', 'K2607-29-A',           'K2607-29-A',               54561.95, 'Deposit in transit'),
    ('101020107', 'DIT', '2026-07-30', 'K2607-30-A',           'K2607-30-A',               79048.25, 'Deposit in transit'),
    ('101020107', 'DIT', '2026-07-31', 'K2607-31-A',           'K2607-31-A',               55024.20, 'Deposit in transit'),
    ('101020107', 'DIT', '2026-07-31', 'M2607-31-A',           'M2607-31-A',               44058.20, 'Deposit in transit'),
    ('101020107', 'OC',  '2026-06-29', 'V2606-131M3084291367', 'V2606-131 / M3084291367', 450000.00, 'Outstanding check'),
    ('101020107', 'OC',  '2026-06-29', 'V2606-132M3084291368', 'V2606-132 / M3084291368', 300000.00, 'Outstanding check'),
    ('101020107', 'OC',  '2026-07-27', 'V2607-148M3084291376', 'V2607-148 / M3084291376', 250000.00, 'Outstanding check'),
    ('101020107', 'OC',  '2026-07-31', 'V2607-172M3084291383', 'V2607-172 / M3084291383', 200000.00, 'Outstanding check'),
    ('101020107', 'OC',  '2026-07-31', 'V2607-173M3084291384', 'V2607-173 / M3084291384', 300000.00, 'Outstanding check'),
    ('101020107', 'OC',  '2026-07-31', 'GJ 2607-066',          'GJ 2607-066',              54701.91, 'Add (Less) Other'),
    ('101020107', 'OC',  '2026-07-31', 'GJ 2607-067',          'GJ 2607-067',              85962.68, 'Add (Less) Other'),
    -- MBTC 2
    ('101020108', 'OC',  '2026-07-31', 'GJ 2607-043',          'GJ 2607-043',              18625.79, 'Add (Less) Other');

BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h INNER JOIN @Acct AS a ON a.AccountCode = h.AccountCode
               WHERE h.BranchCode = @Branch AND h.PeriodEnd = @PeriodEnd AND h.Status = 'LOCKED')
        THROW 93101, 'A July 31 recon period of these accounts is LOCKED; reopen it first.', 1;

    -- 1. July 31 headers
    INSERT INTO dbo.BankReconHeader (BranchCode, AccountCode, PeriodEnd, BankStatementBal, GLBookBalance, Status, Remarks, CreatedBy, CreatedDate)
    SELECT @Branch, a.AccountCode, @PeriodEnd, 0, 0, 'OPEN', NULL, @User, GETDATE()
    FROM @Acct AS a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h
                      WHERE h.BranchCode = @Branch AND h.AccountCode = a.AccountCode AND h.PeriodEnd = @PeriodEnd);

    UPDATE h
    SET BankStatementBal = a.BankBal,
        GLBookBalance    = ISNULL(gl.GLBalance, 0),
        Remarks          = 'Balance forward from Peachtree (July 2026 reconciliation, sheet ' + a.Sheet + ')',
        LastUpdatedBy    = @User,
        LastUpdatedDate  = GETDATE()
    FROM dbo.BankReconHeader AS h
    INNER JOIN @Acct AS a ON a.AccountCode = h.AccountCode
    CROSS APPLY dbo.fn_BankRecon_GLBalance(h.AccountCode, h.PeriodEnd) AS gl
    WHERE h.BranchCode = @Branch AND h.PeriodEnd = @PeriodEnd;

    -- 2. Peachtree open items
    INSERT INTO dbo.BankStatementRecon
        (BranchCode, AccountCode, PeriodEnd, ItemType, ReferenceNo, ItemDate, Payee, Amount, Remarks, IsResolved,
         AddedBy, DateTimeAdded, SourceModule, SourceRef, HeaderID, CreatedBy, CreatedDate, ControlNo)
    SELECT @Branch, i.AccountCode, @PeriodEnd, i.ItemType, i.ReferenceNo, i.ItemDate, 'PEACHTREE BALANCE FORWARD', i.Amount,
           'Peachtree July 2026 recon (' + a.Sheet + '): ' + i.Section + ' ' + i.PeachtreeRef, 0,
           @User, GETDATE(), 'BF-PEACHTREE', i.PeachtreeRef, h.HeaderID, @User, GETDATE(), i.PeachtreeRef
    FROM @Item AS i
    INNER JOIN @Acct AS a ON a.AccountCode = i.AccountCode
    INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = @Branch AND h.AccountCode = i.AccountCode AND h.PeriodEnd = @PeriodEnd
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BankStatementRecon AS b
                      WHERE b.AccountCode = i.AccountCode AND b.SourceModule = 'BF-PEACHTREE' AND b.ReferenceNo = i.ReferenceNo);

    -- 3. Post-check: every July 31 header must show Peachtree's own difference
    DECLARE @bad NVARCHAR(2000);
    SELECT @bad = STRING_AGG(CAST(a.AccountCode + ' diff ' + CONVERT(VARCHAR(30), f.Difference) + ' expected ' + CONVERT(VARCHAR(30), a.ExpectedDiff) AS NVARCHAR(MAX)), '; ')
    FROM @Acct AS a
    INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = @Branch AND h.AccountCode = a.AccountCode AND h.PeriodEnd = @PeriodEnd
    CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
    WHERE f.Difference <> a.ExpectedDiff;
    IF @bad IS NOT NULL
    BEGIN
        SET @bad = N'July 31 figures do not match the Peachtree sheet: ' + @bad;
        THROW 93102, @bad, 1;
    END;

COMMIT TRANSACTION;

-- Result
SELECT h.HeaderID, h.AccountCode, a.Sheet, f.BankStatementBal, f.GLBookBalance, f.OpenDIT, f.OpenOC, f.AdjustedBankBalance, f.AdjustedBookBalance, f.Difference
FROM @Acct AS a
INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = @Branch AND h.AccountCode = a.AccountCode AND h.PeriodEnd = @PeriodEnd
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
ORDER BY h.AccountCode;
