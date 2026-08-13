SET NOCOUNT ON;
PRINT '=== sp_CreditMemo: reversal-ticket rewrite (mirrors sp_ConfirmOrder via CM-CLIENT-VAT/VATEX) ===';
GO
EXEC sp_rename 'dbo.sp_CreditMemo', 'sp_CreditMemo_OLD_08052026123519';
GO
SET QUOTED_IDENTIFIER ON;
GO
-- CreditMemo is the audit table this SP re-runs against to skip rows already
-- posted (see CHANGELOG [2]/[6] below). It was keyed on (PONumber,ProductCode)
-- only, which collides: the same PONumber+ProductCode can legitimately appear
-- on more than one DeliveryDetails row (multiple SeqNo -- e.g. partial
-- deliveries of the same product against one PO). Widening the key to the
-- full DeliveryDetails identity (DeliveryNo, ReferenceNumber, SeqNo) fixes
-- that collision. Additive/nullable -- safe for existing readers (Reporting/
-- CreditMemoRepDevEx.cs uses SELECT *).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.CreditMemo') AND name = 'SeqNo')
    ALTER TABLE dbo.CreditMemo ADD DeliveryNo varchar(20) NULL, ReferenceNumber varchar(20) NULL, SeqNo decimal(18,0) NULL;
GO
-- Lines the caller (CreditMemoDevEx.cs) wants applied this run: which
-- DeliveryDetails row (by SeqNo+ProductNo, scoped to @parmpono) and the
-- ActualQty the user entered in the grid. Replaces the old per-row
-- "UPDATE DeliveryDetails ... WHERE ProductNo=... AND SeqNo=..." loop that
-- ran once per grid row from C# (N round trips, and it never touched
-- Variance -- see CHANGELOG [7]).
IF TYPE_ID('dbo.tt_CreditMemoLines') IS NULL
    CREATE TYPE dbo.tt_CreditMemoLines AS TABLE
    (
        SeqNo     decimal(10,0) NOT NULL,
        ProductNo char(5)       NOT NULL,
        ActualQty decimal(10,3) NOT NULL
    );
GO
-- =============================================
-- Author:      Eulz Avancena (original branch: sp_CreditMemo_09132018); rewritten 2026-08-05
-- Description: Credit Memo for a client order (Orders/POForApproval.cs -> CreditMemoDevEx.cs).
--              Applies the qty/amount adjustment recorded on DeliveryDetails
--              (ActualQty vs QtyDelivered -> Variance) and, when the order was already
--              confirmed (@parmstat='DELIVERED'), books REVERSAL GL tickets against the
--              SI-VAT / SI-VATEX tickets sp_ConfirmOrder already posted -- using the
--              existing CM-CLIENT-VAT / CM-CLIENT-VATEX JournalEntryMapping mnemonics
--              (DR Sales / DR Output Tax Payable / CR AR / DR Inventory-restored /
--              CR COGS-reversed), posted through the same sp_PostCompoundTicketSales
--              engine sp_ConfirmOrder uses.
--
-- CHANGELOG FROM sp_CreditMemo (legacy, now sp_CreditMemo_OLD_08052026123519):
--   [1] Reversal ticket entries added. The old version only wrote ad hoc
--       TicketMaster/TicketDetails rows against TransactionDefinition codes
--       CRMemV/CRMemVO/CrMemVE -- it never reversed the Inventory/COGS legs
--       that sp_ConfirmOrder booked, and those tickets weren't wired through
--       JournalEntryMapping like every other modernized ticket in this system.
--       This version posts through sp_PostCompoundTicketSales using the
--       CM-CLIENT-VAT / CM-CLIENT-VATEX mnemonics (already defined in
--       JournalEntryMapping), which mirror-reverse AR, Sales, VAT Output, and
--       Inventory/COGS -- a true reversal of what was booked at Confirm Order.
--   [2] Re-run / re-open safety. The old version recomputed totals from EVERY
--       row on the PO with Variance<>0 on every run -- so opening the Credit
--       Memo form a second time for the same PO (e.g. to process a second
--       returned item later) re-summed and re-posted amounts that were
--       already ticketed the first time (double-booked GL + double-deducted
--       TransactionChargeSales.Balance). This version scopes each run to only
--       the DeliveryDetails rows not yet present in the CreditMemo audit
--       table for this PO (matched on the full row identity -- see [6] --
--       not just PONumber+ProductCode), and throws if there is nothing new
--       to process.
--   [3] TransactionChargeSales.Balance/DiscountAmount crash fix. The old
--       UPDATE assigned a bare correlated subquery (no SUM) to
--       DiscountAmount/Balance -- if more than one product on the PO had a
--       nonzero Variance in the same run, SQL Server raises "Subquery
--       returned more than 1 value" and the whole Credit Memo fails. Now
--       aggregated with SUM(), and applied as a DELTA (+DiscountAmount,
--       -Balance) instead of an overwrite, consistent with [2].
--   [4] ClientLedger now posts to the Credit column (AR decreases), not
--       Debit -- the old version put the Credit Memo amount in the Debit
--       column, which would have increased the customer's AR balance instead
--       of reducing it. Keyed AccountKey=AccountID=CustomerKey, matching the
--       convention sp_PostCompoundTicketSales already uses for SI-VAT/VATEX.
--   [5] @parmstat <> 'DELIVERED' path (Credit Memo opened from the "For
--       Delivery" tab, before Confirm Order / before any ticket exists) is
--       preserved as a ledger-only note -- no reversal ticket, because
--       nothing was posted yet for sp_ConfirmOrder to reverse.
--   [6] CreditMemo audit table widened (DeliveryNo/ReferenceNumber/SeqNo
--       added) so the [2] re-run guard can't collide when the same product
--       appears on more than one DeliveryDetails row for the same PO -- this
--       happens in production data today (partial/repeat deliveries of the
--       same ProductNo under one PONumber). Deliberately NOT keyed off
--       DeliveryDetails.isReturned -- that flag belongs to the separate Sales
--       Return feature (Orders/ReturnSalesOrder.cs, view_BranchOrderDetails)
--       and setting it here would silently hide rows from that unrelated
--       workflow.
--   [7] @Lines TVP added (dbo.tt_CreditMemoLines). CreditMemoDevEx.cs used to
--       loop the grid client-side and fire one raw "UPDATE DeliveryDetails
--       SET ActualQty=...,isCreditMemo=1 WHERE ProductNo=... AND SeqNo=..."
--       per changed row -- N round trips, outside this SP's transaction, and
--       critically it never set Variance (only sp_CreditMemo did, and only
--       as a whole-PO recompute that ran AFTER the old #CMBatch selection --
--       so a same-day first run would filter on Variance<>0 against a
--       column nothing had updated yet). Now the caller passes the edited
--       (SeqNo, ProductNo, ActualQty) rows in one TVP, and this SP sets
--       ActualQty + Variance + isCreditMemo together, in the same statement,
--       inside the same transaction as the ticket posting -- eliminating the
--       ordering bug structurally rather than papering over it.
--
-- The previous version is preserved as sp_CreditMemo_OLD_08052026123519.
-- =============================================
CREATE PROCEDURE [dbo].[sp_CreditMemo]
    @parmpono varchar(10),
    @parmuser varchar(30),
    @parmstat varchar(30),
    @Lines    dbo.tt_CreditMemoLines READONLY
AS
BEGIN
    SET NOCOUNT ON;
    -- XACT_ABORT OFF (default) -- sp_PostCompoundTicketSales is called inside this
    -- transaction; rollback is managed explicitly in CATCH (same rationale documented
    -- in sp_ConfirmOrder for nested-SP calls).

    DECLARE
        @custkey                CHAR(8),
        @custname                VARCHAR(100),
        @custbranch              CHAR(3),
        @effectivitydate         DATE,
        @invoiceno               VARCHAR(20),
        @Particulars             VARCHAR(6999),
        @totaldiscount           MONEY,
        @totaldiscountvatable    MONEY,
        @totaldiscountvatexempt  MONEY,
        @totalvatablesales       MONEY,
        @totalvatoutput          MONEY,
        @totalvatcost            MONEY,
        @totalvatexcost          MONEY,
        @ticketnumvat            VARCHAR(10) = ' ',
        @ticketnumvatex          VARCHAR(10) = ' ';

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
            THROW 59002, 'No lines submitted for this Credit Memo.', 1;

        -- ── Apply the grid edits: ActualQty, Variance, and the flag together ──
        -- WHERE isCreditMemo=0 preserves the old guard's intent: a row already
        -- flagged (i.e. already posted by an earlier successful run) is left
        -- untouched rather than silently re-edited by a stale/resubmitted grid.
        UPDATE dd
           SET dd.ActualQty    = l.ActualQty,
               dd.Variance     = dd.QtyDelivered - l.ActualQty,
               dd.isCreditMemo = 1
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND dd.isCreditMemo = 0;

        -- ── Scope this run to exactly the submitted lines that produced a
        -- real variance and aren't already posted ─────────────────────────
        -- Matched on the full DeliveryDetails identity (DeliveryNo,
        -- ReferenceNumber, SeqNo, ProductNo) -- see CHANGELOG [6]. PONumber+
        -- ProductCode alone is not unique: the same product can appear on
        -- multiple SeqNo rows under one PO (partial/repeat deliveries).
        SELECT dd.DeliveryNo, dd.ReferenceNumber, dd.SeqNo, dd.ProductNo, dd.ProductName,
               dd.QtyDelivered, dd.ActualQty, dd.Variance, dd.SellingPrice, dd.Cost, dd.isVat
        INTO #CMBatch
        FROM DeliveryDetails dd
        JOIN @Lines l
          ON dd.SeqNo     = l.SeqNo
         AND dd.ProductNo = l.ProductNo
        WHERE dd.PONumber = @parmpono
          AND ISNULL(dd.Variance, 0) <> 0
          AND NOT EXISTS (
              SELECT 1 FROM CreditMemo cm
              WHERE cm.PONumber         = dd.PONumber
                AND cm.ProductCode      = dd.ProductNo
                AND cm.DeliveryNo       = dd.DeliveryNo
                AND cm.ReferenceNumber  = dd.ReferenceNumber
                AND cm.SeqNo            = dd.SeqNo
          );

        IF NOT EXISTS (SELECT 1 FROM #CMBatch)
            THROW 59001, 'No new Credit Memo variance to process for this PO (already processed, or ActualQty unchanged).', 1;

        -- ── Keep DeliverySummary in sync (whole-PO recompute; cheap, always correct) ─
        UPDATE DeliverySummary
           SET TotalActualQty         = (SELECT SUM(ActualQty) FROM DeliveryDetails WHERE PONumber=@parmpono),
               TotalVarianceVat       = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=1),
               TotalVarianceVatExempt = (SELECT SUM(Variance) FROM DeliveryDetails WHERE PONumber=@parmpono AND isVat=0)
         WHERE PONumber = @parmpono;

        -- ── Batch totals (this run only) ───────────────────────────────────
        SELECT
            @totaldiscount          = SUM(ISNULL(Variance*SellingPrice,0)),
            @totaldiscountvatable   = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totaldiscountvatexempt = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*SellingPrice,0) ELSE 0 END),
            @totalvatcost           = SUM(CASE WHEN isVat=1 THEN ISNULL(Variance*Cost,0) ELSE 0 END),
            @totalvatexcost         = SUM(CASE WHEN isVat=0 THEN ISNULL(Variance*Cost,0) ELSE 0 END)
        FROM #CMBatch;

        SET @totalvatablesales = ISNULL(@totaldiscountvatable,0) / 1.12;
        SET @totalvatoutput    = @totalvatablesales * 0.12;

        SELECT @custkey = Customer, @effectivitydate = EffectivityDate
        FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

        SELECT @invoiceno = InvoiceNo FROM DeliverySummary WHERE PONumber = @parmpono;

        SELECT @custbranch = BranchCode, @custname = CustomerName
        FROM Customers WHERE CustomerKey = @custkey;

        SET @custbranch = '888';

        SET @Particulars =
            'CREDIT MEMO | Customer: ' + ISNULL(@custname,'')
            + ' | PO: ' + @parmpono
            + ' | Invoice: ' + ISNULL(@invoiceno,'');

        IF @parmstat = 'DELIVERED'
        BEGIN
            -- ── VATable reversal: mirror-reverses SI-VAT ───────────────────
            IF ISNULL(@totaldiscountvatable,0) <> 0
            BEGIN
                DECLARE @AmtCMVat dbo.tt_AmountBreakdown;
                DECLARE @TokCMVat dbo.tt_TokenResolution;
                DECLARE @FlgCMVat dbo.tt_ConditionFlags;

                INSERT @AmtCMVat VALUES
                    ('GROSS', ROUND(@totaldiscountvatable,2)),
                    ('NET',   ROUND(@totalvatablesales,2)),
                    ('VAT',   ROUND(@totalvatoutput,2)),
                    ('VATEX', 0),
                    ('COST',  ROUND(ISNULL(@totalvatcost,0),2));

                INSERT @FlgCMVat VALUES ('HasVAT', 1), ('HasVATEX', 0);

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VAT',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @custbranch,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtCMVat,
                    @Tokens          = @TokCMVat,
                    @Flags           = @FlgCMVat,
                    @LedgerType      = NULL;   -- ClientLedger written below (Credit side)

                SELECT TOP 1 @ticketnumvat = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VAT'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNVat DECIMAL(7,0);
                SELECT @TRNVat = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNVat, @custkey, @custkey, @effectivitydate, @custbranch,
                     @Particulars, 'CM-CLIENT-VAT', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totaldiscountvatable,2), 0, @invoiceno,
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatable,2), 0, @ticketnumvat);
            END;

            -- ── VAT-exempt reversal: mirror-reverses SI-VATEX ───────────────
            IF ISNULL(@totaldiscountvatexempt,0) <> 0
            BEGIN
                DECLARE @AmtCMVatEx dbo.tt_AmountBreakdown;
                DECLARE @TokCMVatEx dbo.tt_TokenResolution;
                DECLARE @FlgCMVatEx dbo.tt_ConditionFlags;

                INSERT @AmtCMVatEx VALUES
                    ('GROSS', ROUND(@totaldiscountvatexempt,2)),
                    ('COST',  ROUND(ISNULL(@totalvatexcost,0),2));

                EXEC [dbo].[sp_PostCompoundTicketSales]
                    @Mnemonic        = 'CM-CLIENT-VATEX',
                    @TicketDate      = @effectivitydate,
                    @BranchCode      = @custbranch,
                    @ReferenceNumber = @parmpono,
                    @ReferenceKey    = @invoiceno,
                    @Particulars     = @Particulars,
                    @Owner           = @custname,
                    @PreparedBy      = @parmuser,
                    @Status          = 'POSTED',
                    @Amounts         = @AmtCMVatEx,
                    @Tokens          = @TokCMVatEx,
                    @Flags           = @FlgCMVatEx,
                    @LedgerType      = NULL;

                SELECT TOP 1 @ticketnumvatex = TicketNumber
                FROM TicketMaster
                WHERE ReferenceNumber = @parmpono AND Mnemonic = 'CM-CLIENT-VATEX'
                ORDER BY TRY_CAST(TicketNumber AS INT) DESC;

                DECLARE @TRNVatEx DECIMAL(7,0);
                SELECT @TRNVatEx = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNVatEx, @custkey, @custkey, @effectivitydate, @custbranch,
                     @Particulars, 'CM-CLIENT-VATEX', @effectivitydate, @parmpono, @invoiceno,
                     @invoiceno, 0, 0, ROUND(@totaldiscountvatexempt,2), 0, @invoiceno,
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscountvatexempt,2), 0, @ticketnumvatex);
            END;
        END
        ELSE
        BEGIN
            -- Not yet confirmed: sp_ConfirmOrder hasn't posted anything for this PO
            -- yet, so there is nothing to reverse -- ledger note only (matches legacy).
            IF ISNULL(@totaldiscount,0) <> 0
            BEGIN
                DECLARE @TRNPre DECIMAL(7,0);
                SELECT @TRNPre = ISNULL(MAX(TRN_SEQ_NO),0)+1 FROM ClientLedger WHERE AccountID = @custkey;

                INSERT INTO ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch,
                     Description, TransCode, TransactionDate, ReferenceNumber, ReferenceKey,
                     InvoiceNo, BeginningBalance, Debit, Credit, EndingBalance, ORNumber,
                     TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@TRNPre, @custkey, @custkey, CAST(GETDATE() AS date), @custbranch,
                     'Credit Memo Adjustment (pre-confirm)', 'ADJ', CAST(GETDATE() AS date),
                     @parmpono, @parmpono, 'NON', 0, 0, ROUND(@totaldiscount,2), 0, 'NON',
                     @parmuser, '*', 'Credit Memo', ROUND(@totaldiscount,2), 0, ' ');
            END;
        END;

        -- ── AR adjustment (delta, not overwrite; SUM fixes the multi-row crash) ─
        UPDATE TransactionChargeSales
           SET DiscountAmount = ISNULL(DiscountAmount,0) + ISNULL(@totaldiscount,0),
               Balance        = Balance - ISNULL(@totaldiscount,0)
         WHERE CustomerKey = @custkey
           AND ReferenceNo = @parmpono
           AND InvoiceNo   = @invoiceno;

        -- ── Audit trail (also drives the re-run guard above on future calls) ──
        INSERT INTO CreditMemo
            (PONumber, ProductCode, Description, Qty, ActualQty, Variance,
             SellingPrice, TotalAmount, DiscountAmount, TicketRefNo, DateAdded, ExecuteBy,
             DeliveryNo, ReferenceNumber, SeqNo)
        SELECT
            @parmpono, ProductNo, ProductName, QtyDelivered, ActualQty, Variance,
            SellingPrice, (ActualQty*SellingPrice), (Variance*SellingPrice),
            CASE WHEN isVat=1 THEN @ticketnumvat ELSE @ticketnumvatex END,
            CAST(GETDATE() AS date), @parmuser,
            DeliveryNo, ReferenceNumber, SeqNo
        FROM #CMBatch;

        DROP TABLE IF EXISTS #CMBatch;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DROP TABLE IF EXISTS #CMBatch;

        DECLARE @EMsg  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ESev  INT            = ERROR_SEVERITY();
        DECLARE @ESt   INT            = ERROR_STATE();
        DECLARE @ELine INT            = ERROR_LINE();
        DECLARE @EProc NVARCHAR(128)  = ISNULL(ERROR_PROCEDURE(), 'sp_CreditMemo');
        RAISERROR('Error in %s (line %d): %s', @ESev, @ESt, @EProc, @ELine, @EMsg);
    END CATCH;
END;
GO
PRINT 'DEPLOYMENT COMPLETE: sp_CreditMemo rewritten, original preserved as sp_CreditMemo_OLD_08052026123519.';
