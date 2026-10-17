/* ================================================================
   [110] 2026-10-18  Cancelled CR (collection receipt) records, like the cancelled cheques of [55]-[57]
   ================================================================
   User (2026-10-17): "We need to create a module for cancelled CR just like what we did in cancelled voucher where we
   can add and state the reason why."

   RULES
   - A cancelled CR = a collection receipt (PaymentHeader.CRNo series) that was spoiled / misprinted / damaged / lost /
     voided and never used for a payment. It is RECORDED (branch, CR no., date, reason, remarks, who / when); it posts
     nothing (no payment, no GL, no ledger, no bank recon). A CR already used by a payment is not this: that payment is
     reversed (Client Payments › Edit / reversal).
   - The branch is the CR booklet's branch = the customer's branch, as in the Collection Receipt Register ([92]).
   - Same CR = same branch and the same series + number (fn_rpt_DocNoSplit: 'O-CR-11241' = 'O-CR-011241'), or the same
     text when it has no trailing digits.
   - Refused: no branch / unknown branch 59751, blank CR no. 59752, no reason 59753, a date after today 59754, already
     recorded as cancelled 59755, on a live payment (not REVERSED) of the branch 59756, record not found (edit) 59757,
     busy 59759. A CR no. held only by REVERSED payments may be recorded as cancelled.
   - Edit = typo fixes (branch, CR no., date, reason, remarks) with the same checks; the old and new values are kept in
     CancelledCollectionReceiptEditLog; a save that changes nothing writes nothing. No delete (like the cheques).
   - Collection Receipt Register lists each cancelled CR in its series (Status CANCELLED, Note "CANCELLED: <reason>",
     amounts 0), so it no longer shows as a GAP; a cancelled CR also on a live payment shows as DUPLICATE.
   - Client Payments (new exe) checks the CR no. before posting (sp_FindCancelledCR). NOT a trigger on PaymentHeader:
     both payment screens insert the header with OUTPUT INSERTED.PaymentHeaderID without INTO, which an enabled
     trigger refuses (334). Exception Center S11 lists a cancelled CR that is on a live payment. So the payment-side
     guard is best-effort: the CANCELCR applock serializes only the cancelled-CR writers, a payment posted at the same
     moment (or by an old exe / another writer) is not stopped, and S11 is the safety net.
   - CRKey (series + number, as above) is stored on the record with a unique index (branch, CRKey), so the same CR can't
     be recorded twice however it is typed, even by a writer that skips the procs (web v2: compute it the same way).

   New tables CancelledCollectionReceipt / CancelledCollectionReceiptEditLog; new procs spu_RecordCancelledCR,
   spu_EditCancelledCR, sp_GetCancelledCRs, sp_FindCancelledCR; sp_rpt_CollectionReceiptRegister recreated (guard = its
   live hash 88151455…, identical on DEV / STAGING / PRODUCTION 10-18; backup _OLD_10182026100000; same columns).
   Error codes 59751–59759 unused before. Exe: the old exe works on it (register rows added); the new exe has the screen.
   Run in ONE connection with no open transaction.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET LOCK_TIMEOUT 10000;
GO

IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('[110] stopped: this session already has an open transaction (COMMIT / ROLLBACK it first); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.CancelledCollectionReceipt', 'U') IS NOT NULL
BEGIN
    RAISERROR('[110] already applied in this database; nothing changed.', 10, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.fn_rpt_DocNoSplit') IS NULL OR OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister', 'P') IS NULL
BEGIN
    RAISERROR('[110] stopped: needs [92] (fn_rpt_DocNoSplit, sp_rpt_CollectionReceiptRegister); nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister_OLD_10182026100000') IS NOT NULL
     OR OBJECT_ID('dbo.spu_RecordCancelledCR') IS NOT NULL OR OBJECT_ID('dbo.spu_EditCancelledCR') IS NOT NULL
     OR OBJECT_ID('dbo.sp_GetCancelledCRs') IS NOT NULL OR OBJECT_ID('dbo.sp_FindCancelledCR') IS NOT NULL
BEGIN
    RAISERROR('[110] stopped: a backup or one of the new procs already exists; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister')), CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 2)
        <> '881514554CA737F0B62DD7BB50ECE0974E7F09CD36D4B7D6177964E40F3E4C3D'
BEGIN
    RAISERROR('[110] stopped: sp_rpt_CollectionReceiptRegister is not the [92] text this script was written against; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO
PRINT '[110] database: ' + DB_NAME() + ' on ' + @@SERVERNAME;
BEGIN TRANSACTION;
GO

-- ── tables ───────────────────────────────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE TABLE dbo.CancelledCollectionReceipt
(
    CancelledCRID  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CancelledCollectionReceipt PRIMARY KEY,
    BranchCode     VARCHAR(10)   NOT NULL,
    CRNo           VARCHAR(20)   NOT NULL,
    CRKey          VARCHAR(60)   NOT NULL,   -- series + number (fn_rpt_DocNoSplit), unique per branch: the same CR however it was typed
    CRDate         DATE          NOT NULL,
    Reason         VARCHAR(100)  NOT NULL,
    Remarks        VARCHAR(1000) NULL,
    RecordedBy     VARCHAR(50)   NOT NULL,
    RecordedAt     DATETIME      NOT NULL CONSTRAINT DF_CancelledCollectionReceipt_RecordedAt DEFAULT (GETDATE()),
    RecordedHost   VARCHAR(128)  NULL     CONSTRAINT DF_CancelledCollectionReceipt_RecordedHost DEFAULT (HOST_NAME()),
    ModifiedBy     VARCHAR(50)   NULL,
    ModifiedAt     DATETIME      NULL
);
CREATE UNIQUE INDEX UX_CancelledCollectionReceipt_Branch_CRKey ON dbo.CancelledCollectionReceipt (BranchCode, CRKey);
CREATE INDEX IX_CancelledCollectionReceipt_CRDate ON dbo.CancelledCollectionReceipt (CRDate);

CREATE TABLE dbo.CancelledCollectionReceiptEditLog
(
    LogID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CancelledCollectionReceiptEditLog PRIMARY KEY,
    CancelledCRID  INT           NOT NULL,
    OldBranchCode  VARCHAR(10)   NULL,  NewBranchCode VARCHAR(10)   NULL,
    OldCRNo        VARCHAR(20)   NULL,  NewCRNo       VARCHAR(20)   NULL,
    OldCRDate      DATE          NULL,  NewCRDate     DATE          NULL,
    OldReason      VARCHAR(100)  NULL,  NewReason     VARCHAR(100)  NULL,
    OldRemarks     VARCHAR(1000) NULL,  NewRemarks    VARCHAR(1000) NULL,
    EditedBy       VARCHAR(50)   NOT NULL,
    EditedAt       DATETIME      NOT NULL CONSTRAINT DF_CancelledCollectionReceiptEditLog_EditedAt DEFAULT (GETDATE()),
    EditedHost     VARCHAR(128)  NULL     CONSTRAINT DF_CancelledCollectionReceiptEditLog_EditedHost DEFAULT (HOST_NAME())
);
CREATE INDEX IX_CancelledCollectionReceiptEditLog_CR ON dbo.CancelledCollectionReceiptEditLog (CancelledCRID);
GO

-- ── record ───────────────────────────────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_RecordCancelledCR
    @BranchCode VARCHAR(10),
    @CRNo       VARCHAR(20),
    @CRDate     DATE,
    @Reason     VARCHAR(100),
    @Remarks    VARCHAR(1000) = NULL,
    @User       VARCHAR(128)
AS
/*  [110] 2026-10-18: records a spoiled / misprinted / damaged / lost CR as cancelled. Posts nothing.
    Refuses 59751–59756 / 59759 (see the [110] script header). Returns CancelledCRID, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @msg NVARCHAR(600), @rc INT, @id INT, @key VARCHAR(60),
            @who VARCHAR(50) = LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@User)), ''), SUSER_SNAME()), 50);

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @BranchCode = NULLIF(LTRIM(RTRIM(@BranchCode)), '');
        SET @CRNo       = UPPER(NULLIF(LTRIM(RTRIM(@CRNo)), ''));
        SET @Reason     = UPPER(NULLIF(LTRIM(RTRIM(@Reason)), ''));
        SET @Remarks    = NULLIF(LTRIM(RTRIM(@Remarks)), '');

        IF @BranchCode IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
            THROW 59751, 'Pick the branch whose CR booklet it is.', 1;
        IF @CRNo IS NULL
            THROW 59752, 'Enter the CR number.', 1;
        IF @Reason IS NULL
            THROW 59753, 'State the reason the CR was cancelled.', 1;
        IF @CRDate IS NULL OR @CRDate > CAST(GETDATE() AS DATE)
            THROW 59754, 'The CR date must be today or earlier.', 1;

        EXEC @rc = sp_getapplock @Resource = N'CANCELCR', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @rc < 0
            THROW 59759, 'Another cancelled CR is being saved; try again.', 1;

        SELECT @key = CASE WHEN SeqNo IS NULL THEN 'X:' + UPPER(CleanNo) ELSE Series + ':' + CAST(SeqNo AS VARCHAR(20)) END
        FROM dbo.fn_rpt_DocNoSplit(@CRNo);

        SELECT TOP (1) @msg = CONCAT(N'CR no. ', x.CRNo, N' of branch ', x.BranchCode, N' is already recorded as cancelled (',
                                    CONVERT(CHAR(10), x.CRDate, 23), N', ', x.Reason, N', by ', x.RecordedBy, N'). Edit that record instead.')
        FROM dbo.CancelledCollectionReceipt AS x
        WHERE x.BranchCode = @BranchCode AND x.CRKey = @key
        ORDER BY x.CancelledCRID;
        IF @msg IS NOT NULL THROW 59755, @msg, 1;

        SELECT TOP (1) @msg = CONCAT(N'CR no. ', ph.CRNo, N' is on payment ', ph.ReferenceNo, N' (', CONVERT(CHAR(10), ph.PaymentDate, 23), N', ',
                                    ph.CustomerKey, N' - ', c.CustomerName, N'). A CR used by a payment can''t be cancelled here: reverse the payment.')
        FROM dbo.PaymentHeader AS ph
        INNER JOIN dbo.Customers AS c ON c.CustomerKey = ph.CustomerKey
        CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) AS s
        WHERE c.BranchCode = @BranchCode
          AND ISNULL(ph.Status, '') <> 'REVERSED'
          AND CASE WHEN s.SeqNo IS NULL THEN 'X:' + UPPER(s.CleanNo) ELSE s.Series + ':' + CAST(s.SeqNo AS VARCHAR(20)) END = @key
        ORDER BY ph.PaymentHeaderID;
        IF @msg IS NOT NULL THROW 59756, @msg, 1;

        INSERT dbo.CancelledCollectionReceipt (BranchCode, CRNo, CRKey, CRDate, Reason, Remarks, RecordedBy)
        VALUES (@BranchCode, @CRNo, @key, @CRDate, @Reason, @Remarks, @who);
        SET @id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
        SELECT @id AS CancelledCRID, CONCAT('CR no. ', @CRNo, ' of branch ', @BranchCode, ' recorded as CANCELLED (', @Reason, ').') AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ── edit ─────────────────────────────────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.spu_EditCancelledCR
    @CancelledCRID INT,
    @BranchCode    VARCHAR(10),
    @CRNo          VARCHAR(20),
    @CRDate        DATE,
    @Reason        VARCHAR(100),
    @Remarks       VARCHAR(1000) = NULL,
    @User          VARCHAR(128)
AS
/*  [110] 2026-10-18: corrects a recorded cancelled CR (typos); same checks as spu_RecordCancelledCR, not counting the
    record itself; logs the old / new values. A save that changes nothing writes nothing. Returns CancelledCRID, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @msg NVARCHAR(600), @rc INT, @key VARCHAR(60), @changed BIT = 0,
            @who VARCHAR(50) = LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@User)), ''), SUSER_SNAME()), 50),
            @oBranch VARCHAR(10), @oCRNo VARCHAR(20), @oDate DATE, @oReason VARCHAR(100), @oRemarks VARCHAR(1000);

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @BranchCode = NULLIF(LTRIM(RTRIM(@BranchCode)), '');
        SET @CRNo       = UPPER(NULLIF(LTRIM(RTRIM(@CRNo)), ''));
        SET @Reason     = UPPER(NULLIF(LTRIM(RTRIM(@Reason)), ''));
        SET @Remarks    = NULLIF(LTRIM(RTRIM(@Remarks)), '');

        IF @BranchCode IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
            THROW 59751, 'Pick the branch whose CR booklet it is.', 1;
        IF @CRNo IS NULL
            THROW 59752, 'Enter the CR number.', 1;
        IF @Reason IS NULL
            THROW 59753, 'State the reason the CR was cancelled.', 1;
        IF @CRDate IS NULL OR @CRDate > CAST(GETDATE() AS DATE)
            THROW 59754, 'The CR date must be today or earlier.', 1;

        EXEC @rc = sp_getapplock @Resource = N'CANCELCR', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @rc < 0
            THROW 59759, 'Another cancelled CR is being saved; try again.', 1;

        SELECT @oBranch = BranchCode, @oCRNo = CRNo, @oDate = CRDate, @oReason = Reason, @oRemarks = Remarks
        FROM dbo.CancelledCollectionReceipt WITH (UPDLOCK, HOLDLOCK)
        WHERE CancelledCRID = @CancelledCRID;
        IF @oCRNo IS NULL
            THROW 59757, 'That cancelled CR record no longer exists; reload the list.', 1;

        -- a save that changes nothing writes nothing (no RETURN inside the transaction: standard)
        IF NOT (@oBranch = @BranchCode AND @oCRNo = @CRNo AND @oDate = @CRDate AND @oReason = @Reason
                AND ISNULL(@oRemarks, '') = ISNULL(@Remarks, ''))
        BEGIN
            SET @changed = 1;
            SELECT @key = CASE WHEN SeqNo IS NULL THEN 'X:' + UPPER(CleanNo) ELSE Series + ':' + CAST(SeqNo AS VARCHAR(20)) END
            FROM dbo.fn_rpt_DocNoSplit(@CRNo);

            SELECT TOP (1) @msg = CONCAT(N'CR no. ', x.CRNo, N' of branch ', x.BranchCode, N' is already recorded as cancelled (',
                                        CONVERT(CHAR(10), x.CRDate, 23), N', ', x.Reason, N').')
            FROM dbo.CancelledCollectionReceipt AS x
            WHERE x.BranchCode = @BranchCode AND x.CRKey = @key AND x.CancelledCRID <> @CancelledCRID
            ORDER BY x.CancelledCRID;
            IF @msg IS NOT NULL THROW 59755, @msg, 1;

            SELECT TOP (1) @msg = CONCAT(N'CR no. ', ph.CRNo, N' is on payment ', ph.ReferenceNo, N' (', CONVERT(CHAR(10), ph.PaymentDate, 23), N', ',
                                        ph.CustomerKey, N' - ', c.CustomerName, N'). A CR used by a payment can''t be recorded as cancelled.')
            FROM dbo.PaymentHeader AS ph
            INNER JOIN dbo.Customers AS c ON c.CustomerKey = ph.CustomerKey
            CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) AS s
            WHERE c.BranchCode = @BranchCode
              AND ISNULL(ph.Status, '') <> 'REVERSED'
              AND CASE WHEN s.SeqNo IS NULL THEN 'X:' + UPPER(s.CleanNo) ELSE s.Series + ':' + CAST(s.SeqNo AS VARCHAR(20)) END = @key
            ORDER BY ph.PaymentHeaderID;
            IF @msg IS NOT NULL THROW 59756, @msg, 1;

            UPDATE dbo.CancelledCollectionReceipt
            SET BranchCode = @BranchCode, CRNo = @CRNo, CRKey = @key, CRDate = @CRDate, Reason = @Reason, Remarks = @Remarks,
                ModifiedBy = @who, ModifiedAt = GETDATE()
            WHERE CancelledCRID = @CancelledCRID;

            INSERT dbo.CancelledCollectionReceiptEditLog
                (CancelledCRID, OldBranchCode, NewBranchCode, OldCRNo, NewCRNo, OldCRDate, NewCRDate, OldReason, NewReason, OldRemarks, NewRemarks, EditedBy)
            VALUES (@CancelledCRID, @oBranch, @BranchCode, @oCRNo, @CRNo, @oDate, @CRDate, @oReason, @Reason, @oRemarks, @Remarks, @who);
        END

        COMMIT TRANSACTION;
        SELECT @CancelledCRID AS CancelledCRID,
               CASE WHEN @changed = 1 THEN CONCAT('Cancelled CR ', @CRNo, ' of branch ', @BranchCode, ' updated.')
                    ELSE 'No changes: nothing was saved.' END AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ── list ─────────────────────────────────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_GetCancelledCRs
    @DateFrom   DATE = NULL,
    @DateTo     DATE = NULL,
    @BranchCode VARCHAR(10) = NULL    -- NULL / '' / 'ALL' = every branch
AS
/*  [110] 2026-10-18: the recorded cancelled CRs, newest first. Read-only. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @All BIT = CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@BranchCode, ''))), '') IS NULL OR @BranchCode = 'ALL' THEN 1 ELSE 0 END;

    SELECT x.CancelledCRID, x.BranchCode, CONCAT(x.BranchCode, ' - ', b.BranchName) AS Branch,
           x.CRNo, x.CRDate, x.Reason, x.Remarks, x.RecordedBy, x.RecordedAt, x.ModifiedBy, x.ModifiedAt,
           (SELECT COUNT(*) FROM dbo.CancelledCollectionReceiptEditLog AS l WHERE l.CancelledCRID = x.CancelledCRID) AS Edits
    FROM dbo.CancelledCollectionReceipt AS x
    LEFT JOIN dbo.Branches AS b ON b.BranchCode = x.BranchCode
    WHERE (@DateFrom IS NULL OR x.CRDate >= @DateFrom)
      AND (@DateTo IS NULL OR x.CRDate <= @DateTo)
      AND (@All = 1 OR x.BranchCode = @BranchCode)
    ORDER BY x.CRDate DESC, x.BranchCode, x.CRNo;
END;
GO

-- ── find (Client Payments pre-check) ─────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_FindCancelledCR
    @BranchCode VARCHAR(10),
    @CRNo       VARCHAR(20)
AS
/*  [110] 2026-10-18: the cancelled-CR record of this branch with the same series + number, if any (no row = free).
    Client Payments calls it before posting. Read-only. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @key VARCHAR(60);
    SET @CRNo = UPPER(NULLIF(LTRIM(RTRIM(@CRNo)), ''));
    SELECT @key = CASE WHEN SeqNo IS NULL THEN 'X:' + UPPER(CleanNo) ELSE Series + ':' + CAST(SeqNo AS VARCHAR(20)) END
    FROM dbo.fn_rpt_DocNoSplit(@CRNo);

    SELECT TOP (1) x.CancelledCRID, x.BranchCode, x.CRNo, x.CRDate, x.Reason, x.RecordedBy
    FROM dbo.CancelledCollectionReceipt AS x
    WHERE @CRNo IS NOT NULL
      AND x.BranchCode = LTRIM(RTRIM(@BranchCode))
      AND x.CRKey = @key
    ORDER BY x.CancelledCRID;
END;
GO

-- ── Collection Receipt Register: cancelled CRs in their series ───
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
EXEC sp_rename 'dbo.sp_rpt_CollectionReceiptRegister', 'sp_rpt_CollectionReceiptRegister_OLD_10182026100000';
GO
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
CREATE PROCEDURE dbo.sp_rpt_CollectionReceiptRegister
    @DateFrom   DATE,
    @DateTo     DATE,
    @BranchCode VARCHAR(10) = NULL     -- NULL / '' / 'ALL' = all branches (the customer's branch)
AS
/*
    Returns: one row per AR payment (PaymentHeader), payment date in the range,
    sorted by CR No. series and number:
        Branch (the customer's, code - name), Series, CRNo, SeqNo, PaymentDate,
        ControlNo, ReferenceNo, Customer (key - name), PaymentType,
        AmountReceived (PaymentHeader.TotalAmount), AppliedToInvoices, EWT,
        Discount (from ARPaymentDetails, ErrorTag <> 1), Invoices (the invoice
        nos. paid), Status, Note
    Note: DUPLICATE (the CR No. is on more than one payment that is not
    reversed), GAP / JUMP, NO CR NO. / NO NUMBER, REVERSED; judged against every
    receipt of the branch's series (customer branch + prefix), all dates (a reversed receipt's number
    counts as used, and may be typed again on its replacement).
    [110] 2026-10-18: also one row per recorded cancelled CR (CancelledCollectionReceipt), dated its CR date, Status
    CANCELLED, Note "CANCELLED: <reason>", amounts 0; it fills its place in the series (no GAP) and counts as a holder
    of its number (a live payment on it shows DUPLICATE). Backup sp_rpt_CollectionReceiptRegister_OLD_10182026100000.
    Callers: AccountingDevEx/AccountingRegistersFrm (Collection Receipt Register tab). [92] 2026-10-15.
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @All BIT = CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@BranchCode, ''))), '') IS NULL OR @BranchCode = 'ALL' THEN 1 ELSE 0 END;

    ;WITH cr AS (
        SELECT ph.PaymentHeaderID, ph.CRNo, ph.ControlNo, ph.ReferenceNo, ph.CustomerKey, c.CustomerName, c.BranchCode,
               ph.PaymentType, ph.TotalAmount, CAST(ph.PaymentDate AS DATE) AS PaymentDate, ph.Status,
               CASE WHEN ISNULL(ph.Status, '') = 'REVERSED' THEN 1 ELSE 0 END AS IsReversed,
               0 AS IsCancelled, CAST(NULL AS VARCHAR(100)) AS CancelReason,
               sp.Series, sp.SeqNo, sp.CleanNo
        FROM dbo.PaymentHeader AS ph
        LEFT JOIN dbo.Customers AS c
            ON c.CustomerKey = ph.CustomerKey
        CROSS APPLY dbo.fn_rpt_DocNoSplit(ph.CRNo) AS sp
        UNION ALL
        SELECT NULL, x.CRNo, NULL, NULL, NULL, NULL, x.BranchCode,
               NULL, 0, x.CRDate, 'CANCELLED',
               0, 1, x.Reason,
               sp.Series, sp.SeqNo, sp.CleanNo
        FROM dbo.CancelledCollectionReceipt AS x
        CROSS APPLY dbo.fn_rpt_DocNoSplit(x.CRNo) AS sp
    ),
    nums AS (
        SELECT DISTINCT BranchCode, Series, SeqNo FROM cr WHERE SeqNo IS NOT NULL
    ),
    prev AS (
        SELECT BranchCode, Series, SeqNo, LAG(SeqNo) OVER (PARTITION BY BranchCode, Series ORDER BY SeqNo) AS PrevNo
        FROM nums
    ),
    marked AS (
        SELECT r.*,
               SUM(CASE WHEN r.IsReversed = 0 THEN 1 ELSE 0 END)
                   OVER (PARTITION BY r.BranchCode, r.Series, ISNULL(r.SeqNo, -1), CASE WHEN r.SeqNo IS NULL THEN r.CleanNo ELSE '' END) AS LiveSameNo,
               SUM(r.IsCancelled)
                   OVER (PARTITION BY r.BranchCode, r.Series, ISNULL(r.SeqNo, -1), CASE WHEN r.SeqNo IS NULL THEN r.CleanNo ELSE '' END) AS CancelledSameNo,
               pv.PrevNo
        FROM cr AS r
        LEFT JOIN prev AS pv
            ON pv.BranchCode = r.BranchCode AND pv.Series = r.Series AND pv.SeqNo = r.SeqNo
    )
    SELECT
        CONCAT(m.BranchCode, ' - ', br.BranchName)                     AS Branch,
        CASE WHEN m.Series = '' THEN '(no prefix)' ELSE m.Series END   AS Series,
        m.CRNo,
        m.SeqNo,
        m.PaymentDate,
        m.ControlNo,
        m.ReferenceNo,
        CASE WHEN m.IsCancelled = 1 THEN '' ELSE CONCAT(m.CustomerKey, ' - ', m.CustomerName) END AS Customer,
        m.PaymentType,
        CAST(ISNULL(m.TotalAmount, 0) AS DECIMAL(18,2))                AS AmountReceived,
        CAST(ISNULL(det.Applied, 0) AS DECIMAL(18,2))                  AS AppliedToInvoices,
        CAST(ISNULL(det.Ewt, 0) AS DECIMAL(18,2))                      AS EWT,
        CAST(ISNULL(det.Discount, 0) AS DECIMAL(18,2))                 AS Discount,
        inv.Invoices,
        m.Status,
        NULLIF(CONCAT_WS('; ',
            CASE WHEN m.IsCancelled = 1 THEN CONCAT('CANCELLED: ', m.CancelReason) END,
            CASE WHEN m.CleanNo = '' THEN 'NO CR NO.'
                 WHEN m.SeqNo IS NULL THEN 'NO NUMBER (no trailing digits)' END,
            CASE WHEN m.IsReversed = 0 AND m.CleanNo <> '' AND m.LiveSameNo > 1
                 THEN CASE WHEN m.CancelledSameNo > 0
                           THEN CONCAT('DUPLICATE (', m.LiveSameNo - m.CancelledSameNo, ' payment(s) + ', m.CancelledSameNo, ' cancelled CR)')
                           ELSE CONCAT('DUPLICATE (', m.LiveSameNo, ' payments)') END END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo BETWEEN 2 AND 51
                 THEN CONCAT('GAP: ', m.SeqNo - m.PrevNo - 1, ' skipped (', m.PrevNo + 1, CASE WHEN m.SeqNo - m.PrevNo > 2 THEN CONCAT('-', m.SeqNo - 1) ELSE '' END, ')') END,
            CASE WHEN m.PrevNo IS NOT NULL AND m.SeqNo - m.PrevNo > 51
                 THEN CONCAT('JUMP: ', m.SeqNo - m.PrevNo - 1, ' skipped after ', m.PrevNo, ' (check the number typed)') END,
            CASE WHEN m.IsReversed = 1 THEN 'REVERSED' END), '')        AS Note
    FROM marked AS m
    LEFT JOIN dbo.Branches AS br
        ON br.BranchCode = m.BranchCode
    OUTER APPLY (
        SELECT SUM(CASE WHEN d.PaymentType = 'INVOICE PAYMENT' THEN d.Amount ELSE 0 END) AS Applied,
               SUM(CASE WHEN d.PaymentType = 'EWT' THEN d.Amount ELSE 0 END)             AS Ewt,
               SUM(CASE WHEN d.PaymentType = 'DISCOUNT' THEN d.Amount ELSE 0 END)        AS Discount
        FROM dbo.ARPaymentDetails AS d
        WHERE d.PaymentHeaderID = m.PaymentHeaderID
          AND (d.ErrorTag IS NULL OR d.ErrorTag <> 1)
    ) AS det
    OUTER APPLY (
        SELECT STRING_AGG(x.InvoiceNo, ', ') WITHIN GROUP (ORDER BY x.InvoiceNo) AS Invoices
        FROM (SELECT DISTINCT d.InvoiceNo
              FROM dbo.ARPaymentDetails AS d
              WHERE d.PaymentHeaderID = m.PaymentHeaderID
                AND d.PaymentType = 'INVOICE PAYMENT'
                AND LTRIM(RTRIM(ISNULL(d.InvoiceNo, ''))) <> '') AS x
    ) AS inv
    WHERE m.PaymentDate >= @DateFrom
      AND m.PaymentDate <  DATEADD(DAY, 1, @DateTo)
      AND (@All = 1 OR m.BranchCode = @BranchCode)
    ORDER BY m.BranchCode, CASE WHEN m.CleanNo = '' THEN 1 ELSE 0 END, m.Series, CASE WHEN m.SeqNo IS NULL THEN 1 ELSE 0 END, m.SeqNo, m.PaymentHeaderID
    OPTION (RECOMPILE);
END
GO

-- ── post-check ───────────────────────────────────────────────────
IF @@TRANCOUNT = 0 SET NOEXEC ON;
GO
DECLARE @msg NVARCHAR(400);
IF OBJECT_ID('dbo.CancelledCollectionReceipt', 'U') IS NULL OR OBJECT_ID('dbo.CancelledCollectionReceiptEditLog', 'U') IS NULL
    SET @msg = N'a table is missing';
ELSE IF OBJECT_ID('dbo.spu_RecordCancelledCR', 'P') IS NULL OR OBJECT_ID('dbo.spu_EditCancelledCR', 'P') IS NULL
     OR OBJECT_ID('dbo.sp_GetCancelledCRs', 'P') IS NULL OR OBJECT_ID('dbo.sp_FindCancelledCR', 'P') IS NULL
    SET @msg = N'a proc is missing';
ELSE IF ISNULL(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister')), N'') NOT LIKE '%[[]110]%'
     OR OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister_OLD_10182026100000', 'P') IS NULL
    SET @msg = N'the register is not the [110] text, or its backup is missing';
ELSE IF EXISTS (SELECT column_ordinal, name, system_type_id FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister_OLD_10182026100000'), 0)
                EXCEPT
                SELECT column_ordinal, name, system_type_id FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.sp_rpt_CollectionReceiptRegister'), 0))
    SET @msg = N'the register''s columns (order, name or base type) changed';   -- Note grows 262 -> 405 (the CANCELLED text): a length, not a type
IF @msg IS NOT NULL
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @msg = N'[110] post-check failed: ' + @msg + N'; everything rolled back.';
    THROW 59897, @msg, 1;
END
COMMIT TRANSACTION;
PRINT '[110] committed: cancelled CRs can be recorded / edited and show in the Collection Receipt Register.';
GO
SET NOEXEC OFF;
SET LOCK_TIMEOUT -1;
GO
