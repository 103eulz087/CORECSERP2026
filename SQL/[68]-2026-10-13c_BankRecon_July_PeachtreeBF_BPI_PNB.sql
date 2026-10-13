/* ================================================================
   [68] 2026-10-13c: Bank Recon balance forward from Peachtree, July 2026 (part 2: BPI PESO 1, PNB PESO, PNB PESO 2)
   ================================================================
   One-time data load, no object changes. Same rules as [42] 2026-10-07d (part 1: BDO PESO 1 / 2, WB, MBTC 1-1 / 2).
   Source: the accountant's second July Peachtree reconciliation workbook (Google Sheet, 2026-10-13; sheets BPI,
   PNB 1, PNB 2, WEALTHBANK). WEALTHBANK is the same as part 1 (bank 785,223.68, Peachtree's own unreconciled
   1,000,050.00), so it is not loaded again.

   Per account (branch 888):
     * July 31 header: created if missing; BankStatementBal = Peachtree "Ending Bank Balance";
       GLBookBalance = fn_BankRecon_GLBalance.
     * Deposits in transit -> ItemType DIT; outstanding checks -> ItemType OC (ReferenceNo = "CV no. / check no.").
     * Every row: SourceModule 'BF-PEACHTREE', original Peachtree date, Amount positive, IsResolved = 0,
       ControlNo = SourceRef = the Peachtree reference. They carry forward into August until cleared.

   Sheet -> account:   BPI -> 101020109 (BPI PESO 1)   PNB 1 -> 101020111 (PNB PESO)   PNB 2 -> 101020112 (PNB PESO 2)

   Checked before writing (STAGING, 2026-10-13): none of the 14 DIT / 3 OC references exists in BankStatementRecon;
   GL at 07-31: BPI 1,289,835.21 and PNB 2 21,195,077.57 = the sheets; PNB PESO 10,407,816.99 = the sheet's
   10,407,541.99 + 275.00. That 275.00 is AR collection ref 31459 (control F2608-24-A) posted with date 2026-07-24,
   already an open July DIT here, so PNB PESO's July still nets to 0.00 (the control no. suggests 08-24: accountant).

   Expected July 31 difference (Adjusted Bank - Adjusted Book) after the load: 0.00 on all three; the post-check
   refuses anything else. Re-runnable: rows already loaded (same account + SourceModule + ReferenceNo) are skipped;
   a LOCKED July header stops the script.
   ================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PeriodEnd DATE = '2026-07-31', @Branch CHAR(3) = '888', @User VARCHAR(50) = 'BF-PEACHTREE';

DECLARE @Acct TABLE (AccountCode VARCHAR(20) PRIMARY KEY, Sheet VARCHAR(20), BankBal DECIMAL(18,2), ExpectedDiff DECIMAL(18,2));
INSERT INTO @Acct VALUES
    ('101020109', 'BPI',    2589835.21, 0.00),
    ('101020111', 'PNB 1',  8733642.29, 0.00),
    ('101020112', 'PNB 2', 21195077.57, 0.00);

DECLARE @Item TABLE (AccountCode VARCHAR(20), ItemType VARCHAR(5), ItemDate DATE, PeachtreeRef VARCHAR(50),
                     ReferenceNo VARCHAR(150), Amount DECIMAL(18,2), Section VARCHAR(30));
INSERT INTO @Item VALUES
    -- BPI PESO 1: outstanding checks
    ('101020109', 'OC',  '2026-05-31', 'CV2605-126BPI6090301', 'CV2605-126 / BPI6090301', 400000.00, 'Outstanding check'),
    ('101020109', 'OC',  '2026-05-31', 'CV2605-127BPI6090302', 'CV2605-127 / BPI6090302', 450000.00, 'Outstanding check'),
    ('101020109', 'OC',  '2026-05-31', 'CV2605-128BPI6090303', 'CV2605-128 / BPI6090303', 450000.00, 'Outstanding check'),
    -- PNB PESO: deposits in transit
    ('101020111', 'DIT', '2026-07-31', 'B2607-31-A', 'B2607-31-A', 385861.40, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'C2607-31-A', 'C2607-31-A',  96542.15, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-30', 'D2607-30-A', 'D2607-30-A',  97089.00, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'D2607-31-A', 'D2607-31-A',  89013.25, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'E2607-31-A', 'E2607-31-A', 186135.10, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-30', 'F2607-30-A', 'F2607-30-A', 101562.80, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'F2607-31-A', 'F2607-31-A',  54756.00, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'G2607-31-A', 'G2607-31-A',  45025.80, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-30', 'H2607-30-A', 'H2607-30-A', 132947.65, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'H2607-31-A', 'H2607-31-A',  56976.60, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'I2607-31-A', 'I2607-31-A', 231060.70, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-30', 'J2607-30-A', 'J2607-30-A', 134365.85, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'J2607-31-A', 'J2607-31-A',  35752.70, 'Deposit in transit'),
    ('101020111', 'DIT', '2026-07-31', 'L2607-31-A', 'L2607-31-A',  26810.70, 'Deposit in transit');
    -- PNB PESO 2: no open items (bank = book)

BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.BankReconHeader AS h INNER JOIN @Acct AS a ON a.AccountCode = h.AccountCode
               WHERE h.BranchCode = @Branch AND h.PeriodEnd = @PeriodEnd AND h.Status = 'LOCKED')
        THROW 93101, 'A July 31 recon period of these accounts is LOCKED; reopen it first.', 1;

    -- the sheet's own totals, so a typo in the list above can't load
    IF (SELECT SUM(Amount) FROM @Item WHERE AccountCode = '101020109' AND ItemType = 'OC') <> 1300000.00
       OR (SELECT SUM(Amount) FROM @Item WHERE AccountCode = '101020111' AND ItemType = 'DIT') <> 1673899.70
        THROW 93103, 'The item list does not add up to the Peachtree sheet totals (BPI OC 1,300,000.00; PNB DIT 1,673,899.70).', 1;

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

    -- 3. Post-check: every July 31 header must reconcile to 0.00
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

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;

-- Result
SELECT h.HeaderID, h.AccountCode, a.Sheet, f.BankStatementBal, f.GLBookBalance, f.OpenDIT, f.OpenOC, f.AdjustedBankBalance, f.AdjustedBookBalance, f.Difference
FROM @Acct AS a
INNER JOIN dbo.BankReconHeader AS h ON h.BranchCode = @Branch AND h.AccountCode = a.AccountCode AND h.PeriodEnd = @PeriodEnd
CROSS APPLY dbo.fn_BankRecon_Figures(h.HeaderID) AS f
ORDER BY h.AccountCode;
