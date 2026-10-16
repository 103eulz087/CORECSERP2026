/* ================================================================
   [86] 2026-10-14 - Manual JV (multi-branch) edit: keep the original preparer, record who last modified it, skip a save
        that changes nothing
   ================================================================
   User 2026-10-14: in the Manual Journal Voucher screen (HOFormsDevEx/ManualJournalVoucherMultiBranchFrm, Accounting
   Board), Posted tab > Edit loads the voucher into New Entry; "Save Changes" re-posts it even when nothing was touched,
   and the Posted tab then shows the editor as PreparedBy. Add LastModifiedBy / LastModifiedDate for audit.

   Cause: sp_EditManualJournalVoucher deletes the voucher (rows, details, GL tickets, JV bank-recon items) and inserts it
   again with PreparedBy = the editor and DateAdded = now, on every save. PRODUCTION 2026-10-03: 57 vouchers re-saved by
   one user show her as preparer (work log, 10-14 note). Each save also takes a new ticket number and new VoucherIDs,
   and re-creates the JV's bank-recon items open (a cleared item comes back uncleared: hardening H7).

   Changes:
   1. ManualJournalVoucher gets LastModifiedBy VARCHAR(50) NULL and LastModifiedDate DATETIME NULL (new columns at the
      end; every writer inserts with a column list, checked: no positional insert in SQL or C#). Existing rows: NULL
      (the history of earlier edits is not known).
   2. sp_EditManualJournalVoucher (recreated; backup _OLD_10142026233000; same parameters, same result set):
      - the original PreparedBy and DateAdded are carried through the edit; LastModifiedBy = the user, LastModifiedDate =
        now;
      - NOTHING CHANGED -> nothing is re-posted: voucher date, remarks, control no. and the lines (branch, account, debit,
        credit, particulars, in screen order, case-sensitive) are compared with what is stored; if all are equal the proc
        returns Status 0 and "No changes ..." and writes nothing (no new ticket, no new VoucherID, recon items untouched,
        LastModified unchanged). The Allow Cross-Branch tick alone is not a change (it only re-labels the ticket);
      - its GL-ticket delete is scoped to the voucher's own tickets (the TicketNumber its rows carry): it deleted every
        ticket under the reference number, and JV references come from the counter that collides with PO numbers (Known Bug #12; 0 such
        collisions on any tier on 2026-10-14);
      - per-voucher applock 'MANUALJV:<ref>' (59210): two users saving the same voucher no longer interleave;
      - error handling per docs/standards/2026-10-14_Posting_Proc_Error_Handling.md (guards inside the transaction,
        CATCH = IF XACT_STATE() <> 0 ROLLBACK; THROW).
   3. sp_GetPostedManualJournalVouchers (recreated; backup _OLD_10142026233000): adds DatePrepared (MIN DateAdded),
      LastModifiedBy, LastModifiedDate; still one row per reference; ControlNo read from the voucher's own tickets.
      NOTE: PRODUCTION's copy was altered in place on 2026-10-14 12:08 (GROUP BY ReferenceNo, PreparedBy: one row per
      preparer) without a backup; the guard accepts that text too, and this script returns to one row per reference
      (all rows of a reference now carry the same preparer).
   No change for the single-branch form's post (sp_PostManualJournalVoucher) or the multi-branch post: new vouchers get
   LastModified NULL. Works with the current exe (the old exe shows the "No changes" message in its Success box and the
   new columns unformatted); the new exe formats the new columns and shows "No Changes".
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF CHARINDEX('[86]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditManualJournalVoucher'))) > 0
BEGIN
    RAISERROR('[86] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
ELSE
BEGIN
    DECLARE @hEdit VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditManualJournalVoucher')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1);
    DECLARE @hList VARCHAR(66) = CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1);
    IF ISNULL(@hEdit, '') <> '0x287A5C4074B59F11760D97FE74B7328ACFA577B6EE7A5FA61315749C8F906060'          -- 2026-09-25e (DEV = STAGING = PRODUCTION)
       OR ISNULL(@hList, '') NOT IN ('0x8C82AB9FA0420FC2FF91DE01216E85E2C84CED4DCA1A18D2ECD34278976FB86A',   -- 2026-09-23 (DEV, STAGING)
                                     '0x3EE0E51F7F1FE29EC7C03EDBDBA74DEC53A48FCB41DE19D1AE74C721AA1761E6')   -- PRODUCTION, altered 2026-10-14 12:08
       OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026233000')
       OR COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedBy') IS NOT NULL
       OR COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedDate') IS NOT NULL
    BEGIN
        RAISERROR('[86] stopped, nothing changed: sp_EditManualJournalVoucher / sp_GetPostedManualJournalVouchers are not the expected text, or a [86] backup / column already exists.', 16, 1);
        SET NOEXEC ON;
    END
END
GO

BEGIN TRANSACTION;
GO

ALTER TABLE dbo.ManualJournalVoucher ADD
    LastModifiedBy   VARCHAR(50) NULL,
    LastModifiedDate DATETIME    NULL;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[86] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

------------------------------------------------------------------
-- 1. sp_EditManualJournalVoucher
------------------------------------------------------------------
EXEC sp_rename 'dbo.sp_EditManualJournalVoucher', 'sp_EditManualJournalVoucher_OLD_10142026233000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[86] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_EditManualJournalVoucher]
(
    @parmrefno         VARCHAR(10),
    @parmcontrolno     VARCHAR(50),
    @parmvoucherdate   DATE,
    @parmremarks       VARCHAR(500),
    @parmuser          VARCHAR(50),
    @Lines             dbo.JournalVoucherLineMultiTVP_V2 READONLY,   -- 2026-09-25e: V2 (+LineNo)
    @AllowCrossBranch  BIT = 0
)
AS
/*  Edit of a posted manual JV = delete and re-post under the same Reference No (Known Bug Pattern #4: the shape can
    change). [86] 2026-10-14:
      - the original PreparedBy / DateAdded are kept; LastModifiedBy / LastModifiedDate record the edit;
      - a save that changes nothing (date, remarks, control no., lines in screen order) re-posts nothing: Status 0;
      - only the voucher's own tickets (the TicketNumber its rows carry) are deleted, never another document's under the same
        number; a voucher whose GL ticket is missing or does not add up is always re-posted (Save repairs it);
      - applock MANUALJV:<ref> (59210); error handling per docs/standards/2026-10-14_Posting_Proc_Error_Handling.md.
    Result set: Status (1 = re-posted, 0 = no changes), ReferenceNo, BranchesPosted, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NoChange BIT = 0, @maxrow INT = 0;
    DECLARE @origPreparedBy VARCHAR(50), @origDateAdded DATETIME;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Lock INT, @LockRes NVARCHAR(255) = N'MANUALJV:' + @parmrefno;
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 59210, 'Another user is saving this journal voucher right now. Please try again.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher WITH (UPDLOCK, HOLDLOCK) WHERE ReferenceNo = @parmrefno)
            THROW 59201, 'No existing journal voucher found for this Reference No - use the Post function for a new entry.', 1;

        -- [86] the original preparer and date survive every edit
        SELECT TOP (1) @origPreparedBy = PreparedBy, @origDateAdded = DateAdded
        FROM dbo.ManualJournalVoucher
        WHERE ReferenceNo = @parmrefno
        ORDER BY DateAdded, VoucherID;

        ------------------------------------------------------------------
        -- [86] nothing changed -> nothing is re-posted. Stored lines are numbered in the order the screen loads them
        --      (sp_GetManualJournalVoucherDetails: LineNo, BranchCode, DetailID); the screen numbers the lines it sends
        --      1..n in grid order, so an untouched edit sends the same positions.
        ------------------------------------------------------------------
        DECLARE @StoredDate DATE, @StoredRemarks VARCHAR(500), @StoredControlNo VARCHAR(150);
        SELECT @StoredDate = MIN(VoucherDate), @StoredRemarks = MAX(ISNULL(Remarks, ''))
        FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno;
        SELECT TOP (1) @StoredControlNo = tm.ReferenceKey
        FROM dbo.TicketMaster tm
        WHERE tm.ReferenceNumber = @parmrefno
          AND tm.TicketNumber IN (SELECT TicketNumber FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno)   -- the voucher's own ticket(s)
        ORDER BY CASE WHEN tm.ReferenceKey IS NULL THEN 1 ELSE 0 END, tm.TicketNumber;

        IF @StoredDate = @parmvoucherdate
           AND @StoredRemarks COLLATE Latin1_General_CS_AS = ISNULL(@parmremarks, '') COLLATE Latin1_General_CS_AS
           AND ISNULL(@StoredControlNo, '') COLLATE Latin1_General_CS_AS = ISNULL(@parmcontrolno, '') COLLATE Latin1_General_CS_AS
           AND NOT EXISTS (
                SELECT Pos, BranchCode, AccountCode, Debit, Credit, Particulars FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY d.[LineNo], v.BranchCode, d.DetailID) AS Pos,
                           v.BranchCode COLLATE Latin1_General_CS_AS AS BranchCode, d.AccountCode COLLATE Latin1_General_CS_AS AS AccountCode,
                           CAST(ISNULL(d.Debit, 0) AS DECIMAL(18,2)) AS Debit, CAST(ISNULL(d.Credit, 0) AS DECIMAL(18,2)) AS Credit,
                           ISNULL(d.Particulars, '') COLLATE Latin1_General_CS_AS AS Particulars
                    FROM dbo.ManualJournalVoucher v
                    INNER JOIN dbo.ManualJournalVoucherDetails d ON d.VoucherID = v.VoucherID
                    WHERE v.ReferenceNo = @parmrefno) s
                EXCEPT
                SELECT Pos, BranchCode, AccountCode, Debit, Credit, Particulars FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY [LineNo]) AS Pos,
                           BranchCode COLLATE Latin1_General_CS_AS AS BranchCode, AccountCode COLLATE Latin1_General_CS_AS AS AccountCode,
                           CAST(Debit AS DECIMAL(18,2)) AS Debit, CAST(Credit AS DECIMAL(18,2)) AS Credit,
                           ISNULL(Particulars, '') COLLATE Latin1_General_CS_AS AS Particulars
                    FROM @Lines) i)
           AND NOT EXISTS (
                SELECT Pos, BranchCode, AccountCode, Debit, Credit, Particulars FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY [LineNo]) AS Pos,
                           BranchCode COLLATE Latin1_General_CS_AS AS BranchCode, AccountCode COLLATE Latin1_General_CS_AS AS AccountCode,
                           CAST(Debit AS DECIMAL(18,2)) AS Debit, CAST(Credit AS DECIMAL(18,2)) AS Credit,
                           ISNULL(Particulars, '') COLLATE Latin1_General_CS_AS AS Particulars
                    FROM @Lines) i
                EXCEPT
                SELECT Pos, BranchCode, AccountCode, Debit, Credit, Particulars FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY d.[LineNo], v.BranchCode, d.DetailID) AS Pos,
                           v.BranchCode COLLATE Latin1_General_CS_AS AS BranchCode, d.AccountCode COLLATE Latin1_General_CS_AS AS AccountCode,
                           CAST(ISNULL(d.Debit, 0) AS DECIMAL(18,2)) AS Debit, CAST(ISNULL(d.Credit, 0) AS DECIMAL(18,2)) AS Credit,
                           ISNULL(d.Particulars, '') COLLATE Latin1_General_CS_AS AS Particulars
                    FROM dbo.ManualJournalVoucher v
                    INNER JOIN dbo.ManualJournalVoucherDetails d ON d.VoucherID = v.VoucherID
                    WHERE v.ReferenceNo = @parmrefno) s)
            -- [86] and the GL posting is whole: every branch row's ticket exists and the voucher's tickets debit what the voucher says
            -- (a voucher whose ticket is missing or damaged is re-posted by Save Changes, as before)
           AND NOT EXISTS (SELECT 1 FROM dbo.ManualJournalVoucher v WHERE v.ReferenceNo = @parmrefno
                           AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster tm WHERE tm.TicketNumber = v.TicketNumber AND tm.ReferenceNumber = @parmrefno AND tm.BranchCode = v.BranchCode))
           AND (SELECT ISNULL(SUM(td.Debit), 0) FROM dbo.TicketDetails td
                WHERE td.ReferenceNumber = @parmrefno AND td.TicketNumber IN (SELECT TicketNumber FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno))
             = (SELECT ISNULL(SUM(TotalAmount), 0) FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno)
            SET @NoChange = 1;

        IF @NoChange = 0
        BEGIN
            -- guards (unchanged rules and numbers)
            IF (SELECT COUNT(*) FROM @Lines) < 2
                THROW 59202, 'A journal voucher needs at least two lines (one debit, one credit).', 1;

            IF EXISTS (SELECT 1 FROM @Lines WHERE (Debit > 0 AND Credit > 0) OR (Debit = 0 AND Credit = 0))
                THROW 59203, 'Each line must have an amount in either Debit or Credit, not both or neither.', 1;

            IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(AccountCode, ''))) = '')
                THROW 59204, 'Every line requires an Account Code.', 1;

            IF EXISTS (SELECT 1 FROM @Lines WHERE LTRIM(RTRIM(ISNULL(BranchCode, ''))) = '')
                THROW 59205, 'Every line requires a Branch Code.', 1;

            DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
            SELECT @TotalDebit = ISNULL(SUM(Debit), 0), @TotalCredit = ISNULL(SUM(Credit), 0) FROM @Lines;

            IF @TotalDebit <= 0
                THROW 59206, 'Entry total must be greater than zero.', 1;

            IF @TotalDebit <> @TotalCredit
                THROW 59208, 'Entry does not balance overall - total Debit must equal total Credit across all branches.', 1;

            IF @AllowCrossBranch = 0
               AND EXISTS (SELECT BranchCode FROM @Lines GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit))
            BEGIN
                DECLARE @BadBranches VARCHAR(200) = (
                    SELECT STRING_AGG(BranchCode, ', ') FROM (
                        SELECT BranchCode FROM @Lines GROUP BY BranchCode HAVING SUM(Debit) <> SUM(Credit)
                    ) x
                );
                DECLARE @BalanceMsg VARCHAR(400) = 'Entry does not balance per branch. Out-of-balance branch(es): ' + ISNULL(@BadBranches, '')
                    + '. If this is intentional, check "Allow Cross-Branch Entry."';
                THROW 59207, @BalanceMsg, 1;
            END

            -- remove the voucher's own posting: the tickets its rows point at ([86]: was every ticket under the reference number)
            DELETE td
            FROM dbo.TicketDetails td
            WHERE td.ReferenceNumber = @parmrefno
              AND td.TicketNumber IN (SELECT TicketNumber FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno);
            DELETE FROM dbo.TicketMaster
            WHERE ReferenceNumber = @parmrefno
              AND TicketNumber IN (SELECT TicketNumber FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno);
            DELETE FROM dbo.BankStatementRecon WHERE ReferenceNo = @parmrefno AND SourceModule = 'MANUAL-JV';

            DELETE FROM dbo.ManualJournalVoucherDetails
            WHERE VoucherID IN (SELECT VoucherID FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno);
            DELETE FROM dbo.ManualJournalVoucher WHERE ReferenceNo = @parmrefno;

            DECLARE @EditBranches TABLE (RowNum INT PRIMARY KEY, BranchCode VARCHAR(5), BranchTotal DECIMAL(18,2));
            INSERT INTO @EditBranches (RowNum, BranchCode, BranchTotal)
            SELECT ROW_NUMBER() OVER (ORDER BY BranchCode), BranchCode, SUM(Debit) FROM @Lines GROUP BY BranchCode;

            DECLARE @row INT = 1, @br VARCHAR(5), @brTotal DECIMAL(18,2), @ticketnum VARCHAR(20), @voucherID INT;
            SELECT @maxrow = COUNT(*) FROM @EditBranches;
            DECLARE @isMultiBranch BIT = CASE WHEN @maxrow > 1 THEN 1 ELSE 0 END;
            DECLARE @Now DATETIME = GETDATE();

            -- ONE ticket number for the whole voucher, shared across every branch
            EXEC GetTicketNumber @ticketnum OUTPUT;

            WHILE @row <= @maxrow
            BEGIN
                SELECT @br = BranchCode, @brTotal = BranchTotal FROM @EditBranches WHERE RowNum = @row;

                INSERT INTO [dbo].[TicketMaster]
                    (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber,
                     ReferenceNumber, ReferenceKey, Owner, Particulars,
                     EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
                VALUES
                    (@parmvoucherdate, 0, @br, 'JV', @ticketnum,
                     @parmrefno, @parmcontrolno, @parmuser, ISNULL(@parmremarks, ''),
                     @parmuser, '*', '*', 'POSTED',
                     CASE WHEN @AllowCrossBranch = 1 THEN 'MANUAL JV - CROSS-BR'
                          WHEN @isMultiBranch = 1 THEN 'MANUAL JV - MULTI-BR'
                          ELSE 'MANUAL JV' END, NULL);

                INSERT INTO [dbo].[TicketDetails]
                    (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
                     TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
                SELECT @parmvoucherdate, 0, @br, @parmcontrolno, @ticketnum, @parmrefno, AccountCode, Debit, Credit, ''
                FROM @Lines WHERE BranchCode = @br
                ORDER BY [LineNo];

                INSERT INTO dbo.ManualJournalVoucher
                    (ReferenceNo, VoucherDate, BranchCode, Remarks, PreparedBy, DateAdded, TicketNumber, TotalAmount,
                     LastModifiedBy, LastModifiedDate)                                                   -- [86]
                VALUES (@parmrefno, @parmvoucherdate, @br, @parmremarks,
                        ISNULL(@origPreparedBy, @parmuser), ISNULL(@origDateAdded, @Now),               -- [86] the original preparer + date
                        @ticketnum, @brTotal,
                        @parmuser, @Now);                                                               -- [86] who edited, when
                SET @voucherID = SCOPE_IDENTITY();

                INSERT INTO dbo.ManualJournalVoucherDetails (VoucherID, AccountCode, Debit, Credit, Particulars, [LineNo])
                SELECT @voucherID, AccountCode, Debit, Credit, Particulars, [LineNo]
                FROM @Lines WHERE BranchCode = @br
                ORDER BY [LineNo];

                SET @row += 1;
            END;

            EXEC dbo.sp_JV_PostBankReconForLines
                @ReferenceNo = @parmrefno, @VoucherDate = @parmvoucherdate,
                @DefaultBranch = NULL, @CreatedBy = @parmuser;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @NoChange = 1
        SELECT 0 AS Status, @parmrefno AS ReferenceNo, 0 AS BranchesPosted,
               'No changes were made to journal voucher ' + @parmrefno + '; nothing was re-posted.' AS Message;
    ELSE
        SELECT 1 AS Status, @parmrefno AS ReferenceNo, @maxrow AS BranchesPosted,
               'Journal voucher updated successfully.' AS Message;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[86] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

------------------------------------------------------------------
-- 2. sp_GetPostedManualJournalVouchers
------------------------------------------------------------------
EXEC sp_rename 'dbo.sp_GetPostedManualJournalVouchers', 'sp_GetPostedManualJournalVouchers_OLD_10142026233000';
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[86] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO
CREATE PROCEDURE [dbo].[sp_GetPostedManualJournalVouchers]
    @DateFrom         DATE = NULL,
    @DateTo           DATE = NULL,
    @SingleBranchOnly BIT  = 0
AS
/*  Posted tab of both Manual JV screens. One row per reference.
    [86] 2026-10-14: + DatePrepared, LastModifiedBy, LastModifiedDate (edits keep the original PreparedBy);
    ControlNo from the voucher's own tickets (the TicketNumber its rows carry), not any ticket under the same number. */
BEGIN
    SET NOCOUNT ON;

    SELECT
        (
            SELECT TOP 1 tm.ReferenceKey
            FROM dbo.TicketMaster tm
            WHERE tm.ReferenceNumber = a.ReferenceNo
              AND tm.TicketNumber IN (SELECT x.TicketNumber FROM dbo.ManualJournalVoucher x WHERE x.ReferenceNo = a.ReferenceNo)
            ORDER BY CASE WHEN tm.ReferenceKey IS NULL THEN 1 ELSE 0 END, tm.TicketNumber
        )                                                     AS ControlNo,
        a.ReferenceNo,
        MIN(a.VoucherDate)                                   AS VoucherDate,
        MAX(a.Remarks)                                       AS Remarks,
        COUNT(DISTINCT a.BranchCode)                         AS BranchCount,
        MAX(a.BranchCode)                                    AS BranchCode,   -- meaningful only when BranchCount = 1
        CAST(SUM(ISNULL(a.TotalAmount, 0)) AS DECIMAL(18,2)) AS TotalAmount,
        MAX(a.PreparedBy)                                    AS PreparedBy,
        MIN(a.DateAdded)                                     AS DatePrepared,       -- [86]
        MAX(a.LastModifiedBy)                                AS LastModifiedBy,     -- [86]
        MAX(a.LastModifiedDate)                              AS LastModifiedDate    -- [86]
    FROM dbo.ManualJournalVoucher a
    WHERE (@DateFrom IS NULL OR a.VoucherDate >= @DateFrom)
      AND (@DateTo   IS NULL OR a.VoucherDate <= @DateTo)
    GROUP BY a.ReferenceNo
    HAVING (@SingleBranchOnly = 0 OR COUNT(DISTINCT a.BranchCode) = 1)
    ORDER BY MIN(a.VoucherDate) DESC, a.ReferenceNo DESC;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('[86] an earlier step failed and its transaction was rolled back; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

------------------------------------------------------------------
-- post-check
------------------------------------------------------------------
IF COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedBy') IS NULL
   OR COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedDate') IS NULL
   OR (SELECT COUNT(*) FROM sys.objects WHERE name LIKE '%[_]OLD[_]10142026233000') <> 2
   OR OBJECT_ID('dbo.sp_EditManualJournalVoucher') IS NULL OR OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers') IS NULL
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_EditManualJournalVoucher')), '') NOT LIKE '%[[]86]%'
   OR ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetPostedManualJournalVouchers')), '') NOT LIKE '%[[]86]%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[86] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT DB_NAME() AS DatabaseName, name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_EditManualJournalVoucher', 'sp_GetPostedManualJournalVouchers') OR name LIKE '%[_]OLD[_]10142026233000' ORDER BY name;
SELECT 'columns' AS what, COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedBy') AS LastModifiedBy, COL_LENGTH('dbo.ManualJournalVoucher', 'LastModifiedDate') AS LastModifiedDate;
GO
