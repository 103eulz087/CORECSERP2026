/* ================================================================
   2026-09-30: GL month-end period lock (company-wide)
   ================================================================
   Decisions (user, 2026-09-30):
     * Company-wide: one "locked through" date for every branch.
     * Close months in order; a global admin can reopen the LAST closed
       month with a reason. Every close/reopen is logged.
     * Lock covers GL tickets only (TicketDetails / TicketMaster). Every
       posting module writes its ticket in the same transaction, so a
       back-dated expense / JV / voucher / payment into a closed month fails
       as a whole. Modules that don't write tickets (e.g. inventory-only
       adjustments) are not locked by this.

   What the triggers block, for any row dated on/before the locked date:
     TicketDetails : INSERT, DELETE, and UPDATE of TicketDate / BranchCode /
                     AccountCode / Debit / Credit / TicketNumber / ReferenceNumber.
     TicketMaster  : INSERT, DELETE, and UPDATE of TicketDate / BranchCode /
                     TicketNumber / ReferenceNumber / ReferenceKey.
                     Status / Particulars updates stay allowed (sp_ExpenseReversal
                     and payment reversals update the original master's status;
                     the reversing ticket itself is dated today).
   Known effect: edit procs that delete-and-repost (sp_EditSingleExpense,
   sp_EditManualJournalVoucher, sp_EditApprovedExpense,
   sp_EditExpenseManualMultiBranch) are refused for closed months -- the
   correction goes into the open month (or an admin reopens the period).

   Objects (all new):
     dbo.GLPeriodLock        single row (LockID = 1): LockedThroughDate
     dbo.GLPeriodLockLog     CLOSE / REOPEN history
     dbo.sp_GLPeriod_Status  current lock + next period to close + log
     dbo.spu_GLPeriod_Close  close the next month (in order)
     dbo.spu_GLPeriod_Reopen reopen the last closed month (reason required)
     dbo.trg_TicketDetails_PeriodLock, dbo.trg_TicketMaster_PeriodLock

   Error numbers 59900-59919:
     59900 entry dated in a closed period     59904 month doesn't balance (Dr <> Cr)
     59901 period end must be a month end      59905 nothing to reopen
     59902 months must be closed in order      59906 reason required
     59903 can't close the current/future month 59907 lock row missing

   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

-- ----------------------------------------------------------------
-- Tables (new; created only if missing)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.GLPeriodLock', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GLPeriodLock
    (
        LockID            TINYINT      NOT NULL CONSTRAINT PK_GLPeriodLock PRIMARY KEY
                                                CONSTRAINT CK_GLPeriodLock_SingleRow CHECK (LockID = 1),
        LockedThroughDate DATE         NULL,          -- NULL = no month closed yet
        UpdatedBy         VARCHAR(60)  NULL,
        UpdatedAt         DATETIME     NULL
    );
    INSERT INTO dbo.GLPeriodLock (LockID, LockedThroughDate) VALUES (1, NULL);
END
GO

IF OBJECT_ID('dbo.GLPeriodLockLog', 'U') IS NULL
    CREATE TABLE dbo.GLPeriodLockLog
    (
        LogID                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_GLPeriodLockLog PRIMARY KEY,
        Action                 VARCHAR(10)   NOT NULL CONSTRAINT CK_GLPeriodLockLog_Action CHECK (Action IN ('CLOSE', 'REOPEN')),
        PeriodEnd              DATE          NOT NULL,   -- the month closed / reopened
        PreviousLockedThrough  DATE          NULL,
        NewLockedThrough       DATE          NULL,
        Reason                 VARCHAR(500)  NULL,
        ActionBy               VARCHAR(60)   NOT NULL,
        ActionAt               DATETIME      NOT NULL CONSTRAINT DF_GLPeriodLockLog_ActionAt DEFAULT (GETDATE())
    );
GO

-- ----------------------------------------------------------------
-- sp_GLPeriod_Status
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GLPeriod_Status', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GLPeriod_Status', 'sp_GLPeriod_Status_OLD_09302026160000';
GO

CREATE PROCEDURE dbo.sp_GLPeriod_Status
AS
/*
    Result set 1 (one row): LockedThroughDate (NULL = none), NextPeriodToClose
      (the month after the lock, or the first month with tickets), and that
      month's ticket totals (lines, debits, credits) so the closer can see it
      balances.
    Result set 2: the close/reopen log, newest first.
    Caller: AccountingDevEx/GLPeriodClosingFrm.cs.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @Locked DATE = (SELECT LockedThroughDate FROM dbo.GLPeriodLock WHERE LockID = 1);
    DECLARE @Next DATE =
        CASE WHEN @Locked IS NOT NULL THEN EOMONTH(DATEADD(DAY, 1, @Locked))
             ELSE (SELECT EOMONTH(MIN(TicketDate)) FROM dbo.TicketDetails) END;
    DECLARE @NextStart DATE = DATEADD(DAY, 1, EOMONTH(@Next, -1));

    SELECT
        @Locked                                             AS LockedThroughDate,
        @Next                                               AS NextPeriodToClose,
        COUNT(td.TicketNumber)                              AS NextPeriodLines,
        CAST(ISNULL(SUM(ISNULL(td.Debit, 0)), 0)  AS DECIMAL(19,2)) AS NextPeriodDebits,
        CAST(ISNULL(SUM(ISNULL(td.Credit, 0)), 0) AS DECIMAL(19,2)) AS NextPeriodCredits,
        CAST(CASE WHEN @Next IS NOT NULL AND @Next < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS BIT) AS CanCloseNext
    FROM (SELECT 1 AS x) one
    LEFT JOIN dbo.TicketDetails td
           ON td.TicketDate >= @NextStart
          AND td.TicketDate <  DATEADD(DAY, 1, @Next);

    SELECT LogID, Action, PeriodEnd, PreviousLockedThrough, NewLockedThrough, Reason, ActionBy, ActionAt
    FROM dbo.GLPeriodLockLog
    ORDER BY LogID DESC;
END
GO

-- ----------------------------------------------------------------
-- spu_GLPeriod_Close
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_GLPeriod_Close', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_GLPeriod_Close', 'spu_GLPeriod_Close_OLD_09302026160000';
GO

CREATE PROCEDURE dbo.spu_GLPeriod_Close
    @PeriodEnd DATE,              -- last day of the month to close
    @User      VARCHAR(60),
    @Reason    VARCHAR(500) = NULL
AS
/*
    Closes ONE month: the one right after the current lock (or the first
    month with tickets). Refuses a month that hasn't ended yet, and a month
    whose tickets don't balance company-wide (Debit <> Credit).
    Caller: AccountingDevEx/GLPeriodClosingFrm.cs (admin only).
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @PeriodEnd IS NULL OR @PeriodEnd <> EOMONTH(@PeriodEnd)
            THROW 59901, 'The period to close must be a month end (the last day of a month).', 1;

        IF @PeriodEnd >= CAST(GETDATE() AS DATE)
            THROW 59903, 'That month has not ended yet - only a finished month can be closed.', 1;

        DECLARE @msg NVARCHAR(2048);

        BEGIN TRANSACTION;

        DECLARE @Locked DATE;
        SELECT @Locked = LockedThroughDate FROM dbo.GLPeriodLock WITH (UPDLOCK, HOLDLOCK) WHERE LockID = 1;
        IF @@ROWCOUNT = 0
            THROW 59907, 'The period lock row is missing (dbo.GLPeriodLock LockID = 1).', 1;

        DECLARE @Expected DATE =
            CASE WHEN @Locked IS NOT NULL THEN EOMONTH(DATEADD(DAY, 1, @Locked))
                 ELSE ISNULL((SELECT EOMONTH(MIN(TicketDate)) FROM dbo.TicketDetails), @PeriodEnd) END;

        IF @PeriodEnd <> @Expected
        BEGIN
            SET @msg = N'Months must be closed in order. The next month to close is '
                     + CONVERT(NVARCHAR(10), @Expected, 120) + N'.';
            THROW 59902, @msg, 1;
        END

        DECLARE @Dr DECIMAL(19,2), @Cr DECIMAL(19,2);
        SELECT @Dr = ISNULL(SUM(ISNULL(Debit, 0)), 0), @Cr = ISNULL(SUM(ISNULL(Credit, 0)), 0)
        FROM dbo.TicketDetails
        WHERE TicketDate >= DATEADD(DAY, 1, EOMONTH(@PeriodEnd, -1))
          AND TicketDate <  DATEADD(DAY, 1, @PeriodEnd);

        IF @Dr <> @Cr
        BEGIN
            SET @msg = N'This month doesn''t balance: debits ' + CONVERT(NVARCHAR(30), @Dr)
                     + N', credits ' + CONVERT(NVARCHAR(30), @Cr) + N'. Fix the entries before closing.';
            THROW 59904, @msg, 1;
        END

        UPDATE dbo.GLPeriodLock
        SET LockedThroughDate = @PeriodEnd, UpdatedBy = @User, UpdatedAt = GETDATE()
        WHERE LockID = 1;

        INSERT INTO dbo.GLPeriodLockLog (Action, PeriodEnd, PreviousLockedThrough, NewLockedThrough, Reason, ActionBy)
        VALUES ('CLOSE', @PeriodEnd, @Locked, @PeriodEnd, NULLIF(LTRIM(RTRIM(@Reason)), ''), @User);

        COMMIT TRANSACTION;

        SELECT @PeriodEnd AS LockedThroughDate, 'Closed through ' + CONVERT(VARCHAR(10), @PeriodEnd, 120) + '.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- spu_GLPeriod_Reopen
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_GLPeriod_Reopen', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_GLPeriod_Reopen', 'spu_GLPeriod_Reopen_OLD_09302026160000';
GO

CREATE PROCEDURE dbo.spu_GLPeriod_Reopen
    @User   VARCHAR(60),
    @Reason VARCHAR(500)
AS
/*
    Reopens the LAST closed month only (the lock moves back one month; if
    that was the only closed month, nothing stays closed). Reason required;
    logged. The admin-only restriction is enforced by the calling form
    (role flags live in the app, not the database).
    Caller: AccountingDevEx/GLPeriodClosingFrm.cs.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NULLIF(LTRIM(RTRIM(@Reason)), '') IS NULL
            THROW 59906, 'A reason is required to reopen a closed month.', 1;

        BEGIN TRANSACTION;

        DECLARE @Locked DATE;
        SELECT @Locked = LockedThroughDate FROM dbo.GLPeriodLock WITH (UPDLOCK, HOLDLOCK) WHERE LockID = 1;
        IF @@ROWCOUNT = 0
            THROW 59907, 'The period lock row is missing (dbo.GLPeriodLock LockID = 1).', 1;
        IF @Locked IS NULL
            THROW 59905, 'No month is closed, so there is nothing to reopen.', 1;

        -- Back one month; NULL when no earlier CLOSE is still in effect.
        DECLARE @New DATE = EOMONTH(@Locked, -1);
        IF NOT EXISTS (SELECT 1 FROM dbo.GLPeriodLockLog WHERE Action = 'CLOSE' AND PeriodEnd = @New)
            SET @New = NULL;

        UPDATE dbo.GLPeriodLock
        SET LockedThroughDate = @New, UpdatedBy = @User, UpdatedAt = GETDATE()
        WHERE LockID = 1;

        INSERT INTO dbo.GLPeriodLockLog (Action, PeriodEnd, PreviousLockedThrough, NewLockedThrough, Reason, ActionBy)
        VALUES ('REOPEN', @Locked, @Locked, @New, LTRIM(RTRIM(@Reason)), @User);

        COMMIT TRANSACTION;

        SELECT @New AS LockedThroughDate,
               'Reopened ' + CONVERT(VARCHAR(7), @Locked, 120)
             + CASE WHEN @New IS NULL THEN '. No month is closed now.'
                    ELSE '. Closed through ' + CONVERT(VARCHAR(10), @New, 120) + '.' END AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- Triggers
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.trg_TicketDetails_PeriodLock', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.trg_TicketDetails_PeriodLock', 'trg_TicketDetails_PeriodLock_OLD_09302026160000';
GO

CREATE TRIGGER dbo.trg_TicketDetails_PeriodLock
ON dbo.TicketDetails
AFTER INSERT, UPDATE, DELETE
AS
/*
    Rejects any GL line added, removed, or changed (amount, account, date,
    branch, ticket) when it is dated on/before GLPeriodLock.LockedThroughDate.
    The whole statement -- and the caller's transaction -- is rolled back.
*/
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    -- HOLDLOCK: keep a shared lock on the lock row until this transaction ends, so a
    -- concurrent spu_GLPeriod_Close (UPDLOCK then UPDATE) waits for in-flight postings
    -- instead of closing a month under a posting that already passed this check.
    -- Shared locks don't block each other, so postings still run in parallel.
    DECLARE @Locked DATE = (SELECT LockedThroughDate FROM dbo.GLPeriodLock WITH (HOLDLOCK) WHERE LockID = 1);
    IF @Locked IS NULL RETURN;

    -- An UPDATE that touches none of the financial columns is allowed.
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(TicketDate) OR UPDATE(BranchCode) OR UPDATE(AccountCode) OR UPDATE(Debit)
                OR UPDATE(Credit) OR UPDATE(TicketNumber) OR UPDATE(ReferenceNumber)
                OR UPDATE(SupplementaryNumber))
        RETURN;

    IF EXISTS (SELECT 1 FROM inserted WHERE TicketDate < DATEADD(DAY, 1, @Locked))
       OR EXISTS (SELECT 1 FROM deleted WHERE TicketDate < DATEADD(DAY, 1, @Locked))
    BEGIN
        DECLARE @msg NVARCHAR(400) =
            N'The books are closed through ' + CONVERT(NVARCHAR(10), @Locked, 120)
          + N'. GL entries dated on or before that date can''t be added, changed or deleted. '
          + N'Post the correction in an open month, or ask an admin to reopen the period.';
        THROW 59900, @msg, 1;
    END
END
GO

IF OBJECT_ID('dbo.trg_TicketMaster_PeriodLock', 'TR') IS NOT NULL
    EXEC sp_rename 'dbo.trg_TicketMaster_PeriodLock', 'trg_TicketMaster_PeriodLock_OLD_09302026160000';
GO

CREATE TRIGGER dbo.trg_TicketMaster_PeriodLock
ON dbo.TicketMaster
AFTER INSERT, UPDATE, DELETE
AS
/*
    Same rule for ticket headers. Status / Particulars / approval updates stay
    allowed (reversals mark the original ticket; the reversing ticket is
    dated today), only a header's identity/date changes and inserts/deletes
    are blocked in a closed month.
*/
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    -- HOLDLOCK: keep a shared lock on the lock row until this transaction ends, so a
    -- concurrent spu_GLPeriod_Close (UPDLOCK then UPDATE) waits for in-flight postings
    -- instead of closing a month under a posting that already passed this check.
    -- Shared locks don't block each other, so postings still run in parallel.
    DECLARE @Locked DATE = (SELECT LockedThroughDate FROM dbo.GLPeriodLock WITH (HOLDLOCK) WHERE LockID = 1);
    IF @Locked IS NULL RETURN;

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(TicketDate) OR UPDATE(BranchCode) OR UPDATE(TicketNumber)
                OR UPDATE(ReferenceNumber) OR UPDATE(ReferenceKey) OR UPDATE(SupplementaryNumber))
        RETURN;

    IF EXISTS (SELECT 1 FROM inserted WHERE TicketDate < DATEADD(DAY, 1, @Locked))
       OR EXISTS (SELECT 1 FROM deleted WHERE TicketDate < DATEADD(DAY, 1, @Locked))
    BEGIN
        DECLARE @msg NVARCHAR(400) =
            N'The books are closed through ' + CONVERT(NVARCHAR(10), @Locked, 120)
          + N'. GL tickets dated on or before that date can''t be added, re-dated or deleted. '
          + N'Post the correction in an open month, or ask an admin to reopen the period.';
        THROW 59900, @msg, 1;
    END
END
GO
