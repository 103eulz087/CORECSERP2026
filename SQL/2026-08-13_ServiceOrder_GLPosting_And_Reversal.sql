SET NOCOUNT ON;
PRINT '=== Service Order GL posting on approve + reversal on cancel-after-approve ===';
GO

-- =============================================
-- CONTEXT: sp_ApproveServiceOrder (SQL/2026-08-09_ServiceOrder_NewTables_And_SPs.sql)
-- currently only inserts the AR row into TransactionChargeSales (so it shows
-- in Aging) and flips Status='APPROVED' -- it never books anything to the GL
-- ledger (TicketMaster/TicketDetails). This script wires Services into the
-- same mnemonic-driven engine (JournalEntryMapping + sp_PostCompoundTicketSales)
-- Products already use via sp_ConfirmOrder, adds a per-service GL revenue
-- account (Services.GLCode), and adds sp_CancelApprovedServiceOrder to
-- reverse the GL/AR effects if an approved order is later cancelled --
-- modeled directly on sp_ReturnSalesOrder's DELIVERED-path reversal
-- (SQL/2026-08-05_ReturnSalesOrder_TVP_ReversalTicket_Rewrite.sql), the
-- closest existing "reverse an already-posted sales GL ticket" precedent.
--
-- A single Service Order can mix multiple services with DIFFERENT GLCodes,
-- and sp_PostCompoundTicketSales posts one fixed set of legs per call -- so
-- both the posting and reversal procedures below loop once per DISTINCT
-- GLCode found in the order's lines (same technique sp_ConfirmOrder uses to
-- call once per VAT bucket).
-- =============================================

-- ── Schema: per-service default GL revenue account ──────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Services') AND name = 'GLCode')
    ALTER TABLE dbo.Services ADD GLCode VARCHAR(50) NULL;
GO

-- ── Schema: cancel-after-approve tracking on ServiceOrderSummary ────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ServiceOrderSummary') AND name = 'CancelledBy')
    ALTER TABLE dbo.ServiceOrderSummary ADD
        CancelledBy    VARCHAR(50)  NULL,
        DateCancelled  DATETIME     NULL,
        CancelReason   VARCHAR(250) NULL,
        TicketRefNo    VARCHAR(10)  NULL,   -- last GL ticket posted on approve
        RevTicketRefNo VARCHAR(10)  NULL;   -- last reversal ticket, if cancelled
GO

-- ── JournalEntryMapping: original posting + mirror reversal ─────────────
-- {AR} = 101030101, the same "AR Trade" account sp_ConfirmOrder debits for
-- product sales (SI-VAT/SI-VATEX in _tmp_sp_ConfirmOrder_raw.sql) -- product
-- and service AR roll up together, confirmed with the user rather than
-- guessing a separate account.
-- {SERVICE_GL} is resolved per call from Services.GLCode (varies per order,
-- can differ line to line -- see the distinct-GLCode loop in both SPs below).
IF NOT EXISTS (SELECT 1 FROM JournalEntryMapping WHERE Mnemonic = 'SVC-REVENUE')
BEGIN
    INSERT INTO JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, IsConditional, IsAmountFromSource, IsActive, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('SVC', 'SVC-REVENUE', 'Service Order Revenue', 1, 'D', '{AR}',         0, 1, 1, 'GROSS', NULL, NULL),
        ('SVC', 'SVC-REVENUE', 'Service Order Revenue', 2, 'C', '{SERVICE_GL}', 0, 1, 1, 'GROSS', NULL, NULL);
END
GO

IF NOT EXISTS (SELECT 1 FROM JournalEntryMapping WHERE Mnemonic = 'SVC-REVENUE-REV')
BEGIN
    INSERT INTO JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, IsConditional, IsAmountFromSource, IsActive, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('SVC', 'SVC-REVENUE-REV', 'Service Order Revenue Reversal', 1, 'C', '{AR}',         0, 1, 1, 'GROSS', NULL, NULL),
        ('SVC', 'SVC-REVENUE-REV', 'Service Order Revenue Reversal', 2, 'D', '{SERVICE_GL}', 0, 1, 1, 'GROSS', NULL, NULL);
END
GO

-- =============================================
-- Author:      Eulz Avancena (original 2026-08-09); GL posting added 2026-08-13
-- Description: Approves a Service Order. Unchanged from the original: still
--              posts the AR row to TransactionChargeSales (Aging) and flips
--              Status. NEW: blocks approval if any line's Service has no
--              GLCode configured, then books one SVC-REVENUE GL ticket per
--              distinct GLCode in the order (DR {AR} / CR that service's
--              account) via sp_PostCompoundTicketSales, same engine
--              sp_ConfirmOrder uses for product sales, including the
--              built-in ClientLedger (Debit) write via @LedgerType='CLIENT'.
-- =============================================
-- Idempotent re-run guard: only rename-to-backup the FIRST time this script
-- runs against a given database (i.e. only if the timestamped backup name
-- doesn't already exist). A second run in the same environment (e.g. fixing
-- a bug in this same script before it's ever gone live) just replaces the
-- current draft directly -- no value in stacking backups of a version that
-- was never used against real data.
IF OBJECT_ID('dbo.sp_ApproveServiceOrder_OLD_08132026140446', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.sp_ApproveServiceOrder', 'P') IS NOT NULL
        DROP PROCEDURE dbo.sp_ApproveServiceOrder;
END
ELSE IF OBJECT_ID('dbo.sp_ApproveServiceOrder', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.sp_ApproveServiceOrder', 'sp_ApproveServiceOrder_OLD_08132026140446';
END
GO
CREATE PROCEDURE [dbo].[sp_ApproveServiceOrder]
    @SVCNumber   VARCHAR(50),
    @ApprovedBy  VARCHAR(50)
AS
BEGIN
    SET XACT_ABORT OFF;
    -- XACT_ABORT OFF -- sp_PostCompoundTicketSales is called inside this
    -- transaction; rollback is managed explicitly in CATCH (same nested-SP
    -- rationale documented in sp_ConfirmOrder / sp_ReturnSalesOrder).
    SET NOCOUNT ON;

    DECLARE
        @custkey         CHAR(8),
        @custname        VARCHAR(100),
        @branchcode      VARCHAR(50),
        @paymenttype     VARCHAR(10),
        @term            INT,
        @totalAmount     DECIMAL(18,2),
        @invoiceno       VARCHAR(10),
        @effectivitydate DATE = CAST(GETDATE() AS DATE),
        @Particulars     VARCHAR(6999),
        @lastticket      VARCHAR(20),
        @row             INT = 1,
        @maxrow          INT,
        @glcode          VARCHAR(50),
        @glamount        DECIMAL(18,2);

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM dbo.ServiceOrderSummary WHERE SVCNumber = @SVCNumber AND Status = 'FOR APPROVAL')
            THROW 58111, 'This Service Order is not pending approval (already approved/rejected).', 1;

        -- ── Block up front if any line's Service has no GLCode, OR the
        --    ServiceCode no longer matches any Services row at all (LEFT
        --    JOIN, not INNER -- an INNER JOIN here would silently drop an
        --    orphaned/deleted ServiceCode out of this check instead of
        --    catching it, letting that line skip GL posting entirely while
        --    still counting toward the AR total below). ──────────────────
        IF EXISTS (
            SELECT 1 FROM dbo.ServiceOrderDetails d
            LEFT JOIN dbo.Services s ON s.SRVC_ID = d.ServiceCode
            WHERE d.SVCNumber = @SVCNumber AND (s.SRVC_ID IS NULL OR s.GLCode IS NULL)
        )
        BEGIN
            DECLARE @missingcode VARCHAR(50);
            SELECT TOP 1 @missingcode = d.ServiceCode
            FROM dbo.ServiceOrderDetails d
            LEFT JOIN dbo.Services s ON s.SRVC_ID = d.ServiceCode
            WHERE d.SVCNumber = @SVCNumber AND (s.SRVC_ID IS NULL OR s.GLCode IS NULL);

            DECLARE @glerr VARCHAR(300) = 'Cannot approve: Service ''' + @missingcode
                + ''' is missing or has no GL account (GLCode) configured. Set it on the Services screen before approving.';
            THROW 58131, @glerr, 1;
        END;

        SELECT @custkey = CustomerKey, @branchcode = BranchCode, @paymenttype = PaymentType
        FROM dbo.ServiceOrderSummary
        WHERE SVCNumber = @SVCNumber;

        SELECT @custname = CustomerName, @term = ISNULL(Term, 0) FROM dbo.Customers WHERE CustomerKey = @custkey;

        SELECT @totalAmount = ISNULL(SUM(Qty * SellingPrice), 0)
        FROM dbo.ServiceOrderDetails
        WHERE SVCNumber = @SVCNumber;

        EXEC dbo.GetReferenceNumber @invoiceno OUTPUT;

        INSERT INTO dbo.TransactionChargeSales
            (CustomerKey, BranchCode, TransactionDate, ReferenceNo, InvoiceNo,
             TotalAmount, PaymentType, Balance, AmountPaid, PayStatus, DueDate, Remarks)
        VALUES
            (@custkey, @branchcode, @effectivitydate, @SVCNumber, @invoiceno,
             @totalAmount, ISNULL(@paymenttype, ''), @totalAmount, 0, 'UNPAID',
             DATEADD(DAY, @term, @effectivitydate), 'SERVICE CHARGE - ' + @SVCNumber);

        -- ── GL posting: one SVC-REVENUE ticket per distinct Service GLCode ──
        SET @Particulars =
            'SERVICE ORDER | Customer: ' + ISNULL(@custname,'')
            + ' | SVC#: ' + @SVCNumber
            + ' | Invoice: ' + ISNULL(@invoiceno,'');

        SELECT
            ROW_NUMBER() OVER (ORDER BY s.GLCode) AS RowNum,
            s.GLCode,
            SUM(d.Qty * d.SellingPrice) AS LineTotal
        INTO #SvcGL
        FROM dbo.ServiceOrderDetails d
        JOIN dbo.Services s ON s.SRVC_ID = d.ServiceCode
        WHERE d.SVCNumber = @SVCNumber
        GROUP BY s.GLCode;

        SELECT @maxrow = COUNT(*) FROM #SvcGL;

        DECLARE @Amt dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;

        WHILE @row <= @maxrow
        BEGIN
            SELECT @glcode = GLCode, @glamount = LineTotal FROM #SvcGL WHERE RowNum = @row;

            DELETE FROM @Amt; DELETE FROM @Tok; DELETE FROM @Flg;
            INSERT @Amt VALUES ('GROSS', @glamount);
            INSERT @Tok VALUES ('{AR}', '101030101'), ('{SERVICE_GL}', @glcode);

            EXEC [dbo].[sp_PostCompoundTicketSales]
                @Mnemonic        = 'SVC-REVENUE',
                @TicketDate      = @effectivitydate,
                @BranchCode      = @branchcode,
                @ReferenceNumber = @SVCNumber,
                @ReferenceKey    = @invoiceno,
                @Particulars     = @Particulars,
                @Owner           = @custname,
                @PreparedBy      = @ApprovedBy,
                @Status          = 'POSTED',
                @Amounts         = @Amt,
                @Tokens          = @Tok,
                @Flags           = @Flg,
                @LedgerType      = 'CLIENT',
                @LedgerEntityID  = @custkey,
                @LedgerInvoiceNo = @invoiceno,
                @LedgerBatchRef  = 0,
                @LedgerSeqRef    = @row;

            SELECT TOP 1 @lastticket = TicketNumber
            FROM dbo.TicketMaster
            WHERE ReferenceNumber = @SVCNumber AND Mnemonic = 'SVC-REVENUE'
            ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

            SET @row += 1;
        END;

        DROP TABLE IF EXISTS #SvcGL;

        UPDATE dbo.ServiceOrderSummary
        SET Status = 'APPROVED',
            ApprovedBy = @ApprovedBy,
            DateApproved = GETDATE(),
            ReferenceNo = @SVCNumber,
            InvoiceNo = @invoiceno,
            TotalAmount = @totalAmount,
            TicketRefNo = @lastticket
        WHERE SVCNumber = @SVCNumber;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #SvcGL;
        DECLARE @EMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev INT = ERROR_SEVERITY();
        DECLARE @ESt  INT = ERROR_STATE();
        RAISERROR('%s', @ESev, @ESt, @EMsg);
    END CATCH
END;
GO

-- =============================================
-- Author:      Eulz Avancena (original); added 2026-08-13
-- Description: Cancels an already-APPROVED Service Order -- the reversal
--              trap for sp_ApproveServiceOrder above. Called from the "Error
--              Correct / Cancelled" right-click menu on gridControlApprovedServices
--              in Orders/POForApproval.cs (contextMenuStripCancelServices ->
--              toolStripMenuItem3_Click_1). Modeled directly on
--              sp_ReturnSalesOrder's DELIVERED-path reversal section
--              (SQL/2026-08-05_ReturnSalesOrder_TVP_ReversalTicket_Rewrite.sql):
--                - TransactionChargeSales is recomputed to zero in place
--                  (TotalAmount/Balance=0, PayStatus='CANCELLED'), not deleted.
--                - GL reversal posts via SVC-REVENUE-REV (D/C swapped) with
--                  @LedgerType=NULL, because sp_PostCompoundTicketSales'
--                  built-in CLIENT-ledger branch is Debit-only -- wrong
--                  direction for a reversal. The Credit-side ClientLedger row
--                  is hand-rolled below, same block sp_ReturnSalesOrder uses.
--                - Which GLCodes/amounts to reverse is read from the ORIGINAL
--                  SVC-REVENUE ticket's TicketDetails rows, not re-derived
--                  from Services.GLCode -- Services.GLCode could have changed
--                  or the Service row been deleted since approval; the ticket
--                  already posted is the only correct source of truth for
--                  what actually needs reversing.
--                - Final status is 'REJECTED', not a separate 'CANCELLED'
--                  value -- reuses POForApproval.cs's existing Rejected tab
--                  (loadRejectedServices()) instead of needing a new one.
--                  RejectedBy/DateRejected/RejectReason are populated for that
--                  view; CancelledBy/DateCancelled/CancelReason are ALSO
--                  populated alongside them purely so this path stays
--                  distinguishable from a genuine pre-approval
--                  sp_RejectServiceOrder rejection (CancelledBy IS NULL there).
--              Payment-touched guard (CLAUDE.md Known Bug Pattern #4): if the
--              service invoice already has AmountPaid > 0, this SP refuses --
--              a paid invoice needs a different manual path, not a silent
--              reversal into an inconsistent state.
-- =============================================
IF OBJECT_ID('dbo.sp_CancelApprovedServiceOrder', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_CancelApprovedServiceOrder;
GO
CREATE PROCEDURE [dbo].[sp_CancelApprovedServiceOrder]
    @SVCNumber    VARCHAR(50),
    @CancelledBy  VARCHAR(50),
    @Reason       VARCHAR(250)
AS
BEGIN
    SET XACT_ABORT OFF;
    SET NOCOUNT ON;

    DECLARE
        @custkey       CHAR(8),
        @custname      VARCHAR(100),
        @branchcode    VARCHAR(50),
        @invoiceno     VARCHAR(10),
        @amountpaid    DECIMAL(18,2),
        @canceldate    DATE = CAST(GETDATE() AS DATE),
        @Particulars   VARCHAR(6999),
        @lastticket    VARCHAR(20),
        @row           INT = 1,
        @maxrow        INT,
        @glcode        VARCHAR(50),
        @glamount      DECIMAL(18,2);

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM dbo.ServiceOrderSummary WHERE SVCNumber = @SVCNumber AND Status = 'APPROVED')
            THROW 58141, 'This Service Order is not in APPROVED status (already error-corrected/rejected, or was never approved).', 1;

        SELECT @custkey = CustomerKey, @branchcode = BranchCode, @invoiceno = InvoiceNo
        FROM dbo.ServiceOrderSummary
        WHERE SVCNumber = @SVCNumber;

        SELECT @custname = CustomerName FROM dbo.Customers WHERE CustomerKey = @custkey;

        SELECT @amountpaid = ISNULL(AmountPaid, 0)
        FROM dbo.TransactionChargeSales
        WHERE ReferenceNo = @SVCNumber AND BranchCode = @branchcode;

        -- ── Payment-touched guard ────────────────────────────────────────
        IF ISNULL(@amountpaid, 0) > 0
            THROW 58142, 'Cannot cancel: this Service Order has already been paid against (partially or fully). Use the payment reversal path instead.', 1;

        -- ── Recompute TransactionChargeSales to zero, in place ───────────
        UPDATE dbo.TransactionChargeSales
        SET TotalAmount = 0,
            Balance = 0,
            PayStatus = 'CANCELLED'
        WHERE ReferenceNo = @SVCNumber AND BranchCode = @branchcode;

        -- ── GL reversal: one SVC-REVENUE-REV ticket per distinct GLCode ──
        SET @Particulars =
            'SERVICE ORDER CANCELLATION | Customer: ' + ISNULL(@custname,'')
            + ' | SVC#: ' + @SVCNumber
            + ' | Invoice: ' + ISNULL(@invoiceno,'')
            + CASE WHEN LEN(ISNULL(@Reason,'')) > 0 THEN ' | Reason: ' + @Reason ELSE '' END;

        -- Reverses exactly what was actually posted at approval time -- read
        -- from TicketDetails (the SVC-REVENUE ticket's credit legs), NOT
        -- re-derived from Services.GLCode. Services.GLCode could have been
        -- changed or the Service row deleted since approval; TicketDetails
        -- is the immutable record of what the books actually show, so it's
        -- the only correct source for what needs to be reversed.
        SELECT
            ROW_NUMBER() OVER (ORDER BY td.AccountCode) AS RowNum,
            td.AccountCode AS GLCode,
            SUM(td.Credit) AS LineTotal
        INTO #SvcGLRev
        FROM dbo.TicketMaster tm
        JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber
        WHERE tm.ReferenceNumber = @SVCNumber
          AND tm.Mnemonic = 'SVC-REVENUE'
          AND td.Credit > 0   -- the {SERVICE_GL} credit legs only, not the {AR} debit leg
        GROUP BY td.AccountCode;

        IF NOT EXISTS (SELECT 1 FROM #SvcGLRev)
            THROW 58143, 'No original SVC-REVENUE GL ticket found for this Service Order -- cannot determine what to reverse.', 1;

        SELECT @maxrow = COUNT(*) FROM #SvcGLRev;

        DECLARE @Amt dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;

        WHILE @row <= @maxrow
        BEGIN
            SELECT @glcode = GLCode, @glamount = LineTotal FROM #SvcGLRev WHERE RowNum = @row;

            DELETE FROM @Amt; DELETE FROM @Tok; DELETE FROM @Flg;
            INSERT @Amt VALUES ('GROSS', @glamount);
            INSERT @Tok VALUES ('{AR}', '101030101'), ('{SERVICE_GL}', @glcode);

            EXEC [dbo].[sp_PostCompoundTicketSales]
                @Mnemonic        = 'SVC-REVENUE-REV',
                @TicketDate      = @canceldate,
                @BranchCode      = @branchcode,
                @ReferenceNumber = @SVCNumber,
                @ReferenceKey    = @invoiceno,
                @Particulars     = @Particulars,
                @Owner           = @custname,
                @PreparedBy      = @CancelledBy,
                @Status          = 'POSTED',
                @Amounts         = @Amt,
                @Tokens          = @Tok,
                @Flags           = @Flg,
                @LedgerType      = NULL;   -- ClientLedger Credit-side written below

            SELECT TOP 1 @lastticket = TicketNumber
            FROM dbo.TicketMaster
            WHERE ReferenceNumber = @SVCNumber AND Mnemonic = 'SVC-REVENUE-REV'
            ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

            DECLARE @ClientTRNSeq DECIMAL(7,0);
            SELECT @ClientTRNSeq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM ClientLedger WHERE AccountID = @custkey;

            INSERT INTO [dbo].[ClientLedger]
                (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                 Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                 InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                 TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
            VALUES
                (@ClientTRNSeq, @custkey, @custkey, @canceldate, @branchcode,
                 @Particulars, 'SVC-REVENUE-REV', @canceldate, @SVCNumber, @invoiceno,
                 @invoiceno, 0, 0, @glamount, 0, @invoiceno,
                 @CancelledBy, '*', LEFT(@Particulars, 50), @glamount, 0, @lastticket);

            SET @row += 1;
        END;

        DROP TABLE IF EXISTS #SvcGLRev;

        -- Status lands on 'REJECTED' (not a separate 'CANCELLED' value) so this
        -- reuses the existing Rejected tab/view_ServiceOrderSummary filtering in
        -- POForApproval.cs (loadRejectedServices() filters on DateRejected) --
        -- no new tab needed. RejectedBy/DateRejected/RejectReason are populated
        -- so it displays correctly there. CancelledBy/DateCancelled/CancelReason
        -- are ALSO populated (in addition to the Rejected* columns) purely so a
        -- post-approval error-correction can still be told apart from a genuine
        -- pre-approval rejection later if ever needed -- CancelledBy IS NULL for
        -- a true sp_RejectServiceOrder rejection, NOT NULL for this path.
        UPDATE dbo.ServiceOrderSummary
        SET Status = 'REJECTED',
            RejectedBy = @CancelledBy,
            DateRejected = GETDATE(),
            RejectReason = @Reason,
            CancelledBy = @CancelledBy,
            DateCancelled = GETDATE(),
            CancelReason = @Reason,
            RevTicketRefNo = @lastticket
        WHERE SVCNumber = @SVCNumber;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #SvcGLRev;
        DECLARE @EMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev INT = ERROR_SEVERITY();
        DECLARE @ESt  INT = ERROR_STATE();
        RAISERROR('%s', @ESev, @ESt, @EMsg);
    END CATCH
END;
GO

PRINT 'DEPLOYMENT COMPLETE: Services.GLCode, ServiceOrderSummary cancel columns, SVC-REVENUE/SVC-REVENUE-REV mnemonics, sp_ApproveServiceOrder (GL posting added), sp_CancelApprovedServiceOrder.';
