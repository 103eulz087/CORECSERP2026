/* ================================================================
   2026-10-01b: STS (stock transfer to branch) lifecycle fixes
   ================================================================
   Found by rolled-back lifecycle tests on COREX001 (docs/CLAUDE_WORKLOG.md,
   Feature 15). Needs script 2026-10-01 (sales order) first: it already
   fixed sp_CancelDeliveryFIFOJFC (all lots restored).

   Bugs:
     1. Saving the same STS twice posted the whole transfer-out again
        (STAGING: POs 11700 / 11701, 3,989,577.64 extra in Inventory In Transit).
     2. The transfer-out (and its return) was split VAT / VAT-exempt by
        InventoryDeliveryFIFO.isVat, which the JFC deduction always wrote as 0,
        while the branch receipt splits by the line's VAT flag: VAT items left
        a balance in both in-transit accounts.
     3. A short receipt (200 kg of 205) left the missing cost in In Transit.
     4. The line cost after Save was one arbitrary lot's cost, so a line that
        spanned lots with different costs received at the wrong cost.
     5. Returning a barcode-scanned line restored the lot to its full original
        quantity (barcode lookup across all branches) instead of what was taken.
     6. Normal receive (sp_AddBranchInventoryBatch): skipped a second line of
        the same product, and wrote receipt ledger rows for cancelled lots too.

   User decision (2026-10-01): a short receipt is a loss at head office:
   DR COS OTHERS (504 VAT / 503 VAT-exempt) / CR In Transit on 888.

   Design: head office's In Transit for a PO must always equal the cost of its
   live (not cancelled / returned) FIFO lots. NEW spu_STS_SyncInTransit posts
   only the difference (IT-HO-* up, ITR-HO-* down), split by each line's VAT
   flag; Save and every return call it, so saving twice posts nothing extra.
   The same procedure repairs old POs (separate correction script).

   Changes:
     A. JournalEntryMapping: STS-SHORT-VAT / -VATEX, STS-OVER-VAT / -VATEX.
     B. NEW spu_STS_SyncInTransit.
     C. sp_SalesQtyToInventoryQtySTS_JFC: FIFO row gets the product's VAT flag.
     D. sp_ConfirmBranchOrderSTS (Save): weighted line cost; posts through B;
        refused once the PO is received.
     E. sp_ReverseSTSInventoryTransfer: on JFC every line (barcode or not) is
        restored lot by lot through sp_CancelDeliveryFIFOJFC; GL through B.
        Non-JFC behaviour unchanged.
     F. sp_ConfirmBranchRecievedOrderJFC: posts the short / over receipt.
     G. sp_AddBranchInventoryBatch: lines matched per barcode; ledger rows only
        for the received lines' live lots.
   Rename-then-create; backups end in _OLD_10012026170000.
   ================================================================ */

-- ----------------------------------------------------------------
-- A. Mapping rows (short / over receipt, booked on head office)
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Mnemonic LIKE 'STS-SHORT-%' OR Mnemonic LIKE 'STS-OVER-%')
BEGIN
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    VALUES
    ('IT','STS-SHORT-VAT',  'STS short receipt - loss at head office (VAT)',        1,'D','504',      'COS OTHERS - VAT',                  0,1,1,'Shipped cost not received by the branch', 'GROSS', NULL, NULL),
    ('IT','STS-SHORT-VAT',  'STS short receipt - loss at head office (VAT)',        2,'C','101040101','INVENTORY IN TRANSIT - VAT',        0,1,1,NULL, 'GROSS', NULL, NULL),
    ('IT','STS-SHORT-VATEX','STS short receipt - loss at head office (VAT exempt)', 1,'D','503',      'COS OTHERS - VAT EXEMPT',           0,1,1,'Shipped cost not received by the branch', 'GROSS', NULL, NULL),
    ('IT','STS-SHORT-VATEX','STS short receipt - loss at head office (VAT exempt)', 2,'C','101040102','INVENTORY IN TRANSIT - VAT EXEMPT', 0,1,1,NULL, 'GROSS', NULL, NULL),
    ('IT','STS-OVER-VAT',   'STS over receipt (VAT)',                               1,'D','101040101','INVENTORY IN TRANSIT - VAT',        0,1,1,'Branch received more cost than shipped', 'GROSS', NULL, NULL),
    ('IT','STS-OVER-VAT',   'STS over receipt (VAT)',                               2,'C','504',      'COS OTHERS - VAT',                  0,1,1,NULL, 'GROSS', NULL, NULL),
    ('IT','STS-OVER-VATEX', 'STS over receipt (VAT exempt)',                        1,'D','101040102','INVENTORY IN TRANSIT - VAT EXEMPT', 0,1,1,'Branch received more cost than shipped', 'GROSS', NULL, NULL),
    ('IT','STS-OVER-VATEX', 'STS over receipt (VAT exempt)',                        2,'C','503',      'COS OTHERS - VAT EXEMPT',           0,1,1,NULL, 'GROSS', NULL, NULL);
END
GO

-- ----------------------------------------------------------------
-- B. Keep head office's In Transit equal to the live shipped cost
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.spu_STS_SyncInTransit', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spu_STS_SyncInTransit', 'spu_STS_SyncInTransit_OLD_10012026170000';
GO
CREATE PROCEDURE dbo.spu_STS_SyncInTransit
    @PONumber    VARCHAR(10),
    @DeliveryNo  VARCHAR(20),
    @DestBranch  VARCHAR(10),
    @User        VARCHAR(50),
    @TicketDate  DATE,
    @HOBranch    VARCHAR(5) = '888'
AS
/*
    Target  = cost of the PO's live FIFO lots (isErrorCorrect = 0), split by
              the delivery line's VAT flag (product flag when no line).
    Posted  = net of IT-HO-* and ITR-HO-* tickets of this PO on @HOBranch,
              on that class's In Transit account (from JournalEntryMapping).
    Posts IT-HO-<class> for a positive difference, ITR-HO-<class> for a
    negative one; nothing when they agree. Receipts (IT-BR-*) and short /
    over receipts (STS-*) are not part of "posted": they settle In Transit
    after delivery. Must run inside the caller's transaction.
    Callers: sp_ConfirmBranchOrderSTS, sp_ReverseSTSInventoryTransfer, correction scripts.
*/
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT = 0
        THROW 59601, 'spu_STS_SyncInTransit must run inside a transaction.', 1;

    SET @DestBranch = ISNULL(@DestBranch, '');
    DECLARE @TransitVat VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VAT' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
    DECLARE @TransitVatEx VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VATEX' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
    IF @TransitVat IS NULL OR @TransitVatEx IS NULL
        THROW 59602, 'JournalEntryMapping IT-HO-VAT / IT-HO-VATEX is missing or inactive.', 1;

    -- serialize per PO so two saves / returns / receives can't interleave
    DECLARE @LockRes NVARCHAR(255) = N'STSTRANSIT:' + @PONumber, @Lock INT;
    EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
    IF @Lock < 0
        THROW 59603, 'Another save or return for this transfer is in progress. Please try again.', 1;

    -- a cancelled / returned line whose lots were never restored means the stock is wrong;
    -- syncing would make the GL disagree with it, so stop and have it repaired first
    IF EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO f
               INNER JOIN dbo.DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
               WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0 AND (dd.isCancelled = 1 OR dd.isReturned = 1))
    BEGIN
        DECLARE @StaleMsg NVARCHAR(400) = N'Transfer ' + @PONumber + N' has cancelled or returned lines whose stock was never put back (active FIFO lots). Repair the stock before posting In Transit.';
        THROW 59605, @StaleMsg, 1;
    END

    -- target: every live lot of the PO (all deliveries, same scope as "posted" below)
    DECLARE @TargetVat DECIMAL(18,2), @TargetVatEx DECIMAL(18,2);
    SELECT @TargetVat   = ISNULL(SUM(CASE WHEN x.isVat = 1 THEN f.TotalCost END), 0),
           @TargetVatEx = ISNULL(SUM(CASE WHEN x.isVat = 0 THEN f.TotalCost END), 0)
    FROM dbo.InventoryDeliveryFIFO f
    OUTER APPLY (SELECT CAST(COALESCE(
                    (SELECT TOP 1 dd.isVat FROM dbo.DeliveryDetails dd
                     WHERE dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo),
                    (SELECT TOP 1 p.isVat FROM dbo.Products p WHERE p.ProductCode = f.ProductNo AND p.BranchCode = @HOBranch),
                    0) AS INT) AS isVat) x
    WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails dd
                      WHERE dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
                        AND (dd.isCancelled = 1 OR dd.isReturned = 1));

    DECLARE @PostedVat DECIMAL(18,2), @PostedVatEx DECIMAL(18,2);
    SELECT @PostedVat   = ISNULL(SUM(CASE WHEN td.AccountCode = @TransitVat   THEN td.Debit - td.Credit END), 0),
           @PostedVatEx = ISNULL(SUM(CASE WHEN td.AccountCode = @TransitVatEx THEN td.Debit - td.Credit END), 0)
    FROM dbo.TicketMaster tm
    INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey = @PONumber AND tm.BranchCode = @HOBranch
      AND tm.Mnemonic IN ('IT-HO-VAT', 'IT-HO-VATEX', 'ITR-HO-VAT', 'ITR-HO-VATEX');

    DECLARE @dVat DECIMAL(18,2) = @TargetVat - @PostedVat, @dVatEx DECIMAL(18,2) = @TargetVatEx - @PostedVatEx;
    IF ABS(@dVat) < 0.01 AND ABS(@dVatEx) < 0.01 RETURN;

    DECLARE @Ref VARCHAR(10), @Particulars VARCHAR(400), @Mn VARCHAR(20), @Amt DECIMAL(18,2), @Pass INT = 1;
    DECLARE @Amts dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;
    DECLARE @Tickets TABLE (TicketNumber VARCHAR(20));
    DECLARE @MaxBefore BIGINT = (SELECT ISNULL(MAX(TRY_CAST(TicketNumber AS BIGINT)), 0) FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber);
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;

    WHILE @Pass <= 2
    BEGIN
        SET @Amt = CASE WHEN @Pass = 1 THEN @dVat ELSE @dVatEx END;
        IF ABS(@Amt) >= 0.01
        BEGIN
            SET @Mn = CASE WHEN @Amt > 0 THEN 'IT-HO-' ELSE 'ITR-HO-' END + CASE WHEN @Pass = 1 THEN 'VAT' ELSE 'VATEX' END;
            SET @Particulars = CASE WHEN @Amt > 0 THEN 'Inventory Transfer Out - PO#' ELSE 'Inventory Transfer RETURN - PO#' END
                               + @PONumber + ' (Branch ' + @DestBranch + ') - ' + CASE WHEN @Pass = 1 THEN 'VATable' ELSE 'VAT Exempt' END;
            DELETE FROM @Amts;
            INSERT @Amts VALUES ('GROSS', ABS(@Amt));
            EXEC dbo.sp_PostCompoundTicket
                @Mnemonic = @Mn, @TicketDate = @TicketDate, @BranchCode = @HOBranch,
                @ReferenceNumber = @Ref, @ReferenceKey = @PONumber, @Particulars = @Particulars,
                @Owner = 'CS IN TRANSIT', @PreparedBy = @User,
                @Amounts = @Amts, @Tokens = @Tok, @Flags = @Flg,
                @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL,
                @LedgerBatchRef = @PONumber, @LedgerSeqRef = @Pass;
        END
        SET @Pass += 1;
    END

    IF EXISTS (SELECT 1 FROM dbo.TicketMaster tm
               INNER JOIN dbo.TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
               WHERE tm.ReferenceKey = @PONumber AND TRY_CAST(tm.TicketNumber AS BIGINT) > @MaxBefore
               GROUP BY tm.TicketNumber HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005)
        THROW 59604, 'Transfer ticket does not balance (DR <> CR). Check the IT-HO / ITR-HO mapping rows.', 1;
END
GO

-- ----------------------------------------------------------------
-- C. FIFO row gets the product's VAT flag (was always 0)
-- ----------------------------------------------------------------
DECLARE @def NVARCHAR(MAX) = REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_SalesQtyToInventoryQtySTS_JFC')), CHAR(13) + CHAR(10), CHAR(10));
DECLARE @old NVARCHAR(MAX) = N'@iSeqNo, 0, 0, ISNULL(@parmsellingprice,0)';
DECLARE @new NVARCHAR(MAX) = N'@iSeqNo, ISNULL((SELECT TOP 1 CAST(p.isVat AS INT) FROM dbo.Products p WHERE p.ProductCode = @parmProduct AND p.BranchCode = @parmorigin), 0) /* 2026-10-01: was 0 */, 0, ISNULL(@parmsellingprice,0)';
IF (LEN(@def) - LEN(REPLACE(@def, @old, ''))) / LEN(@old) <> 1
    THROW 59610, 'sp_SalesQtyToInventoryQtySTS_JFC text differs from the version this script was written for; not changed.', 1;
SET @def = REPLACE(@def, @old, @new);
EXEC sp_rename 'dbo.sp_SalesQtyToInventoryQtySTS_JFC', 'sp_SalesQtyToInventoryQtySTS_JFC_OLD_10012026170000';
EXEC (@def);
GO

-- ----------------------------------------------------------------
-- D. Save (transfer out)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ConfirmBranchOrderSTS', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ConfirmBranchOrderSTS', 'sp_ConfirmBranchOrderSTS_OLD_10012026170000';
GO
CREATE PROCEDURE [dbo].[sp_ConfirmBranchOrderSTS]
(
    @parmdevno           VARCHAR(20),
    @parmrefno           VARCHAR(10),
    @parmeffectivitydate DATE,
    @parmpono            VARCHAR(10),
    @parmbarcode         VARCHAR(50),
    @parmbranchcode      VARCHAR(10),
    @parmorigin          VARCHAR(10), -- not used
    @preparedby          VARCHAR(30)
)
AS
/*
    Save in AddBranchOrderSTS. Costs each line at the weighted cost of all its
    lots, sets the delivery FOR DELIVERY, then spu_STS_SyncInTransit posts
    only what is not yet in In Transit (saving again posts nothing extra).
    Refused once the PO has been received. Same parameters and result set as before.
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @username VARCHAR(50);
        SELECT @username = dbo.func_getUsername(@preparedby);

        IF EXISTS (SELECT 1 FROM DeliverySummary WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND Status = 'DELIVERED')
            THROW 58162, 'This transfer has already been received by the branch; it can no longer be changed here.', 1;

        IF NOT EXISTS (SELECT 1 FROM DeliveryDetails
                       WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0)
            THROW 58161, 'Cannot confirm: no line items found for this delivery. Add at least one product before confirming.', 1;

        -- weighted cost of every live lot the line used
        UPDATE dd
        SET dd.Cost = ISNULL(i.Cost, 0)
        FROM DeliveryDetails dd
        INNER JOIN (SELECT DeliveryNo, PONumber, DevDetSeqNo, ProductNo,
                           SUM(TotalCost) / NULLIF(SUM(QtyDelivered), 0) AS Cost
                    FROM InventoryDeliveryFIFO
                    WHERE isErrorCorrect = 0
                    GROUP BY DeliveryNo, PONumber, DevDetSeqNo, ProductNo) i
            ON dd.DeliveryNo = i.DeliveryNo AND dd.PONumber = i.PONumber AND dd.SeqNo = i.DevDetSeqNo AND dd.ProductNo = i.ProductNo
        WHERE dd.PONumber = @parmpono AND dd.DeliveryNo = @parmdevno;

        SELECT TOP (1) @parmeffectivitydate = EffectivityDate
        FROM TransferOrderSummary WITH (NOLOCK)
        WHERE PONumber = @parmpono;

        DECLARE @totalitem INT, @totalqtydelivered FLOAT;
        SELECT @totalitem = COUNT(*), @totalqtydelivered = SUM(QtyDelivered)
        FROM DeliveryDetails
        WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0;
        SET @totalitem         = ISNULL(@totalitem, 0);
        SET @totalqtydelivered = ISNULL(@totalqtydelivered, 0);

        IF NOT EXISTS (SELECT 1 FROM DeliverySummary WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono)
        BEGIN
            INSERT INTO [dbo].[DeliverySummary]
                ([DeliveryNo],[PONumber],[ReferenceNumber],[InvoiceNo],[BranchCode],
                 [TotalItem],[TotalQtyDelivered],[TotalActualQty],[TotalVarianceVat],
                 [TotalVarianceVatExempt],[EffectivityDate],[Status],[DateAdded],
                 [PreparedBy],[isSettled],[isInvoiceUpdate])
            VALUES
                (@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
                 @totalitem, @totalqtydelivered, 0, 0,
                 0, @parmeffectivitydate, 'FOR DELIVERY', GETDATE(),
                 @preparedby, 0, 0);
        END
        ELSE
        BEGIN
            UPDATE DeliverySummary
            SET TotalItem = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber = @parmpono),
                TotalQtyDelivered = (SELECT ISNULL(SUM(QtyDelivered),0) FROM DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
                TotalItemSold = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0),
                TotalItemReturned = (SELECT ISNULL(COUNT(*),0) FROM DeliveryDetails WHERE PONumber = @parmpono AND isReturned = 1),
                Status = 'FOR DELIVERY'
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;
        END

        EXEC dbo.spu_STS_SyncInTransit
            @PONumber = @parmpono, @DeliveryNo = @parmdevno, @DestBranch = @parmbranchcode,
            @User = @username, @TicketDate = @parmeffectivitydate;

        UPDATE TransferOrderSummary SET isProcess = '1' WHERE PONumber = @parmpono;

        INSERT INTO HistoryLogs
        VALUES (@preparedby, GETDATE(), 'Commissary Process Order with PONumber=' + @parmpono, @parmbranchcode);

        COMMIT TRANSACTION;
        SELECT 1 AS Status, 'Order confirmed and posted.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- E. Return a line (head office Return, or unticked at receiving)
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ReverseSTSInventoryTransfer', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ReverseSTSInventoryTransfer', 'sp_ReverseSTSInventoryTransfer_OLD_10012026170000';
GO
CREATE PROCEDURE [dbo].[sp_ReverseSTSInventoryTransfer]
    @parmdevno       VARCHAR(20),
    @parmrefno       VARCHAR(10),
    @parmpono        VARCHAR(10),
    @parmprodno      VARCHAR(20),
    @parmqty         DECIMAL(18,3),
    @parmbranchcode  VARCHAR(10),
    @parmorigin      VARCHAR(10),
    @preparedby      VARCHAR(30),
    @parmdevseqno    INT,
    @parmbarcode     VARCHAR(100) = NULL
AS
/*
    JFC: every line, barcode-scanned or not, is restored lot by lot through
    sp_CancelDeliveryFIFOJFC (the barcode path used to reset a lot to its full
    original quantity), then spu_STS_SyncInTransit reverses exactly that cost
    from In Transit when the transfer was already saved.
    Other companies: unchanged (barcode / plain cancel + ITR from the corrected lots).
    Callers: AddBranchOrderSTS, ReceivedSTSBatchMode(FIFO), Reporting/StocksOrder,
    DispatchPerBarcode. Same parameters as before.
*/
BEGIN
    SET XACT_ABORT OFF;   -- rollback is managed explicitly in CATCH (nested cancel / posting procs)
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- same per-PO lock as Save / receive / spu_STS_SyncInTransit
        DECLARE @LockRes NVARCHAR(255) = N'STSTRANSIT:' + @parmpono, @Lock INT;
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 59606, 'Another save, return or receive for this transfer is in progress. Please try again.', 1;

        IF EXISTS (SELECT 1 FROM DeliverySummary WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND Status = 'DELIVERED')
            THROW 58163, 'This transfer has already been received by the branch; a line can no longer be returned here.', 1;

        DECLARE @companyname VARCHAR(50);
        SELECT TOP 1 @companyname = CompanyName FROM CompanyProfile;

        IF @companyname = 'JFC'
        BEGIN
            EXEC dbo.sp_CancelDeliveryFIFOJFC
                @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                @parmprodno = @parmprodno, @parmqty = @parmqty, @parmbranchcode = @parmbranchcode,
                @parmorigin = @parmorigin, @preparedby = @preparedby, @parmdevseqno = @parmdevseqno;

            DECLARE @Today DATE = CAST(GETDATE() AS DATE);
            IF EXISTS (SELECT 1 FROM TransferOrderSummary WHERE PONumber = @parmpono AND ISNULL(isProcess, 0) = 1)
                EXEC dbo.spu_STS_SyncInTransit
                    @PONumber = @parmpono, @DeliveryNo = @parmdevno, @DestBranch = @parmbranchcode,
                    @User = @preparedby, @TicketDate = @Today;
        END
        ELSE
        BEGIN
            SELECT SequenceNumber INTO #BeforeSnapshot
            FROM InventoryDeliveryFIFO
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND BranchCode = @parmbranchcode
              AND ProductNo = @parmprodno AND isErrorCorrect = 0;

            IF @parmbarcode IS NOT NULL AND LEN(@parmbarcode) > 0
                EXEC dbo.sp_CancelDeliveryByBarcode
                    @parmbranchcode = @parmbranchcode, @parmorigin = @parmorigin,
                    @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                    @parmbarcode = @parmbarcode, @preparedby = @preparedby;
            ELSE
                EXEC dbo.sp_CancelDelivery
                    @parmdevno = @parmdevno, @parmrefno = @parmrefno, @parmpono = @parmpono,
                    @parmprodno = @parmprodno, @parmqty = @parmqty, @parmbranchcode = @parmbranchcode,
                    @parmorigin = @parmorigin, @preparedby = @preparedby, @parmdevseqno = @parmdevseqno;

            SELECT f.SequenceNumber, f.TotalCost, f.isVat INTO #JustCorrected
            FROM InventoryDeliveryFIFO f INNER JOIN #BeforeSnapshot b ON f.SequenceNumber = b.SequenceNumber
            WHERE f.isErrorCorrect = 1;

            IF EXISTS (SELECT 1 FROM TransferOrderSummary WHERE PONumber = @parmpono AND ISNULL(isProcess, 0) = 1)
               AND EXISTS (SELECT 1 FROM #JustCorrected)
            BEGIN
                DECLARE @totalcostvat MONEY, @totalcostvatex MONEY, @effectivitydate DATE, @outrefnum VARCHAR(10), @Particulars VARCHAR(400);
                SELECT @totalcostvat   = ISNULL(SUM(CASE WHEN isVat = 1 THEN TotalCost ELSE 0 END), 0),
                       @totalcostvatex = ISNULL(SUM(CASE WHEN isVat = 0 THEN TotalCost ELSE 0 END), 0)
                FROM #JustCorrected;
                SELECT TOP 1 @effectivitydate = EffectivityDate FROM TransferOrderSummary WHERE PONumber = @parmpono;
                SET @effectivitydate = ISNULL(@effectivitydate, CAST(GETDATE() AS DATE));
                EXEC GetReferenceNumber @outrefnum OUTPUT;
                DECLARE @AmtsVAT dbo.tt_AmountBreakdown, @TokVAT dbo.tt_TokenResolution, @FlgVAT dbo.tt_ConditionFlags;
                DECLARE @AmtsVE dbo.tt_AmountBreakdown, @TokVE dbo.tt_TokenResolution, @FlgVE dbo.tt_ConditionFlags;
                IF @totalcostvat > 0
                BEGIN
                    INSERT @AmtsVAT VALUES ('GROSS', @totalcostvat);
                    SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VATable';
                    EXEC [dbo].[sp_PostCompoundTicket] @Mnemonic = 'ITR-HO-VAT', @TicketDate = @effectivitydate, @BranchCode = '888',
                        @ReferenceNumber = @outrefnum, @ReferenceKey = @parmpono, @Particulars = @Particulars, @Owner = 'CS IN TRANSIT',
                        @PreparedBy = @preparedby, @Amounts = @AmtsVAT, @Tokens = @TokVAT, @Flags = @FlgVAT,
                        @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL, @LedgerBatchRef = @parmpono, @LedgerSeqRef = 1;
                END
                IF @totalcostvatex > 0
                BEGIN
                    INSERT @AmtsVE VALUES ('GROSS', @totalcostvatex);
                    SET @Particulars = 'Inventory Transfer RETURN - PO#' + @parmpono + ' (from Branch ' + @parmbranchcode + ') - VAT Exempt';
                    EXEC [dbo].[sp_PostCompoundTicket] @Mnemonic = 'ITR-HO-VATEX', @TicketDate = @effectivitydate, @BranchCode = '888',
                        @ReferenceNumber = @outrefnum, @ReferenceKey = @parmpono, @Particulars = @Particulars, @Owner = 'CS IN TRANSIT',
                        @PreparedBy = @preparedby, @Amounts = @AmtsVE, @Tokens = @TokVE, @Flags = @FlgVE,
                        @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL, @LedgerBatchRef = @parmpono, @LedgerSeqRef = 2;
                END
            END
        END

        IF NOT EXISTS (SELECT 1 FROM DeliveryDetails
                       WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND isReturned = 0 AND isCancelled = 0)
            UPDATE DeliverySummary
            SET Status = CASE WHEN Status = 'FOR DELIVERY' THEN 'FOR DELIVERY' ELSE 'PENDING' END
            WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND Status <> 'RETURNED';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- F. Branch confirms the receipt
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_ConfirmBranchRecievedOrderJFC', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_ConfirmBranchRecievedOrderJFC', 'sp_ConfirmBranchRecievedOrderJFC_OLD_10012026170000';
GO
CREATE PROCEDURE [dbo].[sp_ConfirmBranchRecievedOrderJFC]
(
    @parmdevno      VARCHAR(20),
    @parmpono       VARCHAR(10),
    @parmbarcode    VARCHAR(30),
    @parmbranchcode VARCHAR(10),
    @preparedby     VARCHAR(30)
)
AS
/*
    Called after the received lines are recorded (sp_AddBranchInventoryBatch or
    spu_PostSTSReceiveFromFIFO). Marks the transfer DELIVERED, posts the
    receipt on the branch (IT-BR-*: DR branch inventory / CR In Transit at the
    received qty x line cost), then books any difference between the live
    shipped cost and the received cost on head office: STS-SHORT-* (loss,
    DR COS OTHERS / CR In Transit) or STS-OVER-*. Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCounter INT = @@TRANCOUNT;
    IF @TranCounter > 0 SAVE TRANSACTION ConfirmRcvdSave; ELSE BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @LockRes NVARCHAR(255) = N'STSTRANSIT:' + @parmpono, @Lock INT;
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 59607, 'Another save, return or receive for this transfer is in progress. Please try again.', 1;

        IF EXISTS (SELECT 1 FROM DeliverySummary WITH (UPDLOCK) WHERE PONumber = @parmpono AND Status = 'DELIVERED')
        BEGIN
            DECLARE @DoneMsg NVARCHAR(200) = N'PONumber ' + @parmpono + N' has already been confirmed as received.';
            THROW 59608, @DoneMsg, 1;
        END

        UPDATE dt
        SET dt.Status = 'DELIVERED',
            dt.ActualQty = rt.Qty,
            dt.Variance = (dt.QtyDelivered - rt.Qty)
        FROM DeliveryDetails dt
        INNER JOIN ReceivedOrderDetails rt
            ON dt.PONumber = rt.PONumber AND dt.BarcodeNo = rt.Barcode AND dt.ProductNo = rt.ProductCode
        WHERE dt.PONumber = @parmpono AND dt.isCancelled = 0 AND dt.isReturned = 0;

        DECLARE @totalactualqty2 FLOAT = 0, @totalvariancevat FLOAT = 0, @totalvariancevatexempt FLOAT = 0;
        SELECT @totalactualqty2 = ISNULL(SUM(ActualQty), 0),
               @totalvariancevat = ISNULL(SUM(CASE WHEN isVat = 1 THEN ABS(Variance) ELSE 0 END), 0),
               @totalvariancevatexempt = ISNULL(SUM(CASE WHEN isVat = 0 THEN ABS(Variance) ELSE 0 END), 0)
        FROM DeliveryDetails WITH (NOLOCK)
        WHERE PONumber = @parmpono AND isCancelled = 0 AND isReturned = 0;

        UPDATE DeliverySummary
        SET TotalActualQty = @totalactualqty2, TotalVarianceVat = @totalvariancevat,
            TotalVarianceVatExempt = @totalvariancevatexempt, Status = 'DELIVERED'
        WHERE PONumber = @parmpono;

        UPDATE TransferOrderSummary SET Status = 'DELIVERED' WHERE PONumber = @parmpono;

        UPDATE ReceiveOrderSummary
        SET TotalItem = (SELECT ISNULL(COUNT(PONumber), 0) FROM ReceivedOrderDetails WITH (NOLOCK) WHERE PONumber = @parmpono),
            TotalKilo = (SELECT ISNULL(SUM(Qty), 0) FROM ReceivedOrderDetails WITH (NOLOCK) WHERE PONumber = @parmpono)
        WHERE PONumber = @parmpono;

        DECLARE @rcvVat MONEY, @rcvVatEx MONEY;
        SELECT @rcvVat   = ISNULL(SUM(CASE WHEN IsVat = 1 THEN ROUND(Qty * Cost, 2) END), 0),
               @rcvVatEx = ISNULL(SUM(CASE WHEN ISNULL(IsVat, 0) = 0 THEN ROUND(Qty * Cost, 2) END), 0)
        FROM ReceivedOrderDetails WITH (NOLOCK)
        WHERE PONumber = @parmpono;

        DECLARE @outrefnum VARCHAR(10), @Particulars VARCHAR(400), @datekaron DATE = GETDATE();
        EXEC GetReferenceNumber @outrefnum OUTPUT;
        DECLARE @Amts dbo.tt_AmountBreakdown, @Tok dbo.tt_TokenResolution, @Flg dbo.tt_ConditionFlags;

        IF @rcvVat > 0
        BEGIN
            INSERT @Amts VALUES ('GROSS', @rcvVat);
            SET @Particulars = 'Inventory Transfer In - PO#' + @parmpono + ' (' + @parmbranchcode + ') - VATable';
            EXEC [dbo].[sp_PostCompoundTicket] @Mnemonic = 'IT-BR-VAT', @TicketDate = @datekaron, @BranchCode = @parmbranchcode,
                @ReferenceNumber = @outrefnum, @ReferenceKey = @parmpono, @Particulars = @Particulars, @Owner = 'CS IN TRANSIT',
                @PreparedBy = @preparedby, @Amounts = @Amts, @Tokens = @Tok, @Flags = @Flg,
                @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL, @LedgerBatchRef = @parmpono, @LedgerSeqRef = 1;
            DELETE FROM @Amts;
        END
        IF @rcvVatEx > 0
        BEGIN
            INSERT @Amts VALUES ('GROSS', @rcvVatEx);
            SET @Particulars = 'Inventory Transfer In - PO#' + @parmpono + ' (' + @parmbranchcode + ') - VAT Exempt';
            EXEC [dbo].[sp_PostCompoundTicket] @Mnemonic = 'IT-BR-VATEX', @TicketDate = @datekaron, @BranchCode = @parmbranchcode,
                @ReferenceNumber = @outrefnum, @ReferenceKey = @parmpono, @Particulars = @Particulars, @Owner = 'CS IN TRANSIT',
                @PreparedBy = @preparedby, @Amounts = @Amts, @Tokens = @Tok, @Flags = @Flg,
                @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL, @LedgerBatchRef = @parmpono, @LedgerSeqRef = 2;
            DELETE FROM @Amts;
        END

        -- short / over receipt: live shipped cost (by the line's VAT flag) vs received cost
        DECLARE @shipVat MONEY, @shipVatEx MONEY;
        SELECT @shipVat   = ISNULL(SUM(CASE WHEN ISNULL(dd.isVat, 0) = 1 THEN f.TotalCost END), 0),
               @shipVatEx = ISNULL(SUM(CASE WHEN ISNULL(dd.isVat, 0) = 0 THEN f.TotalCost END), 0)
        FROM InventoryDeliveryFIFO f
        INNER JOIN DeliveryDetails dd ON dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber AND dd.SeqNo = f.DevDetSeqNo
        WHERE f.PONumber = @parmpono AND f.isErrorCorrect = 0;

        DECLARE @Pass INT = 1, @Diff MONEY, @Mn VARCHAR(20);
        WHILE @Pass <= 2
        BEGIN
            SET @Diff = ROUND(CASE WHEN @Pass = 1 THEN @shipVat - @rcvVat ELSE @shipVatEx - @rcvVatEx END, 2);
            IF ABS(@Diff) >= 0.01
            BEGIN
                SET @Mn = CASE WHEN @Diff > 0 THEN 'STS-SHORT-' ELSE 'STS-OVER-' END + CASE WHEN @Pass = 1 THEN 'VAT' ELSE 'VATEX' END;
                SET @Particulars = CASE WHEN @Diff > 0 THEN 'Short receipt - PO#' ELSE 'Over receipt - PO#' END + @parmpono
                                   + ' (Branch ' + @parmbranchcode + ') - ' + CASE WHEN @Pass = 1 THEN 'VATable' ELSE 'VAT Exempt' END;
                INSERT @Amts VALUES ('GROSS', ABS(@Diff));
                EXEC [dbo].[sp_PostCompoundTicket] @Mnemonic = @Mn, @TicketDate = @datekaron, @BranchCode = '888',
                    @ReferenceNumber = @outrefnum, @ReferenceKey = @parmpono, @Particulars = @Particulars, @Owner = 'CS IN TRANSIT',
                    @PreparedBy = @preparedby, @Amounts = @Amts, @Tokens = @Tok, @Flags = @Flg,
                    @LedgerType = NULL, @LedgerEntityID = NULL, @LedgerInvoiceNo = NULL, @LedgerBatchRef = @parmpono, @LedgerSeqRef = @Pass;
                DELETE FROM @Amts;
            END
            SET @Pass += 1;
        END

        IF EXISTS (SELECT 1 FROM TicketMaster tm
                   INNER JOIN TicketDetails td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
                   WHERE tm.ReferenceKey = @parmpono AND tm.ReferenceNumber = @outrefnum
                   GROUP BY tm.TicketNumber HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005)
            THROW 59609, 'Receipt ticket does not balance (DR <> CR). Check the IT-BR / STS-SHORT mapping rows.', 1;

        INSERT INTO HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode)
        VALUES (@preparedby, GETDATE(), 'Received/Confirm Order with PONumber=' + @parmpono, @parmbranchcode);

        IF @TranCounter = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranCounter = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK TRANSACTION; END
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION ConfirmRcvdSave;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------
-- G. Normal receive: per-barcode matching, ledger for live lots only
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_AddBranchInventoryBatch', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_AddBranchInventoryBatch', 'sp_AddBranchInventoryBatch_OLD_10012026170000';
GO
CREATE PROCEDURE [dbo].[sp_AddBranchInventoryBatch]
    @PONumber VARCHAR(10),
    @BranchCode VARCHAR(10),
    @ReceivedBy VARCHAR(40),
    @Items dbo.InventoryItemType READONLY
AS
/*
    Records the ticked lines of ReceivedSTSBatchMode. A line is one delivery
    line (product + barcode); a second line of the same product is no longer
    skipped. Receipt ledger rows are written for that line's live lots only.
    Same parameters as before.
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TranCounter INT = @@TRANCOUNT;
    IF @TranCounter > 0 SAVE TRANSACTION AddBatchSave; ELSE BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @LockRes NVARCHAR(255) = N'STSTRANSIT:' + @PONumber, @Lock INT;
        EXEC @Lock = sp_getapplock @Resource = @LockRes, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @Lock < 0
            THROW 59611, 'Another save, return or receive for this transfer is in progress. Please try again.', 1;

        DECLARE @NewItems TABLE (SeqNo INT, DeliveryNo VARCHAR(20), ProductCode CHAR(5), Barcode VARCHAR(60), Qty DECIMAL(15,3),
                                 Cost DECIMAL(18,2), SellingPrice DECIMAL(18,2), ProductName VARCHAR(150), IsVat BIT);
        INSERT INTO @NewItems (SeqNo, DeliveryNo, ProductCode, Barcode, Qty, Cost, SellingPrice, ProductName, IsVat)
        SELECT D.SeqNo, D.DeliveryNo, I.ProductCode, I.Barcode, I.Qty, D.Cost, I.SellingPrice, D.ProductName, D.isVat
        FROM @Items I
        JOIN DeliveryDetails D WITH (UPDLOCK)
          ON D.ProductNo = I.ProductCode AND I.Barcode = D.BarcodeNo AND D.PONumber = @PONumber
         AND D.isCancelled = 0 AND D.isReturned = 0
        WHERE NOT EXISTS (SELECT 1 FROM ReceivedOrderDetails R
                          WHERE R.PONumber = @PONumber AND R.ProductCode = I.ProductCode AND ISNULL(R.Barcode, '') = ISNULL(I.Barcode, ''));

        INSERT INTO ReceivedOrderDetails (SeqNo, PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat)
        SELECT ISNULL((SELECT MAX(SeqNo) FROM ReceivedOrderDetails WHERE PONumber = @PONumber), 0) + ROW_NUMBER() OVER (ORDER BY SeqNo),
               @PONumber, ProductCode, ProductName, Barcode, Qty, Cost, SellingPrice, IsVat
        FROM @NewItems;

        INSERT INTO InventoryLedger
            (SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, Description,
             BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy)
        SELECT f.SequenceReferenceNumber, @BranchCode, @BranchCode, GETDATE(), f.ProductNo, f.Description,
               0, f.QtyDelivered, 0, f.QtyDelivered, f.Cost, 'STS RCVD ITEM PO#' + f.PONumber, @ReceivedBy
        FROM InventoryDeliveryFIFO f
        INNER JOIN @NewItems n ON n.DeliveryNo = f.DeliveryNo AND n.SeqNo = f.DevDetSeqNo
        WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0;

        DECLARE @TotalItem INT, @TotalKilo FLOAT;
        SELECT @TotalItem = ISNULL(COUNT(*), 0), @TotalKilo = ISNULL(SUM(Qty), 0)
        FROM ReceivedOrderDetails WHERE PONumber = @PONumber;
        IF EXISTS (SELECT 1 FROM ReceiveOrderSummary WHERE PONumber = @PONumber)
            UPDATE ReceiveOrderSummary SET TotalItem = @TotalItem, TotalKilo = @TotalKilo WHERE PONumber = @PONumber;
        ELSE
            INSERT INTO ReceiveOrderSummary (PONumber, BranchCode, TotalKilo, TotalItem, DateReceived, ReceivedBy)
            VALUES (@PONumber, @BranchCode, @TotalKilo, @TotalItem, GETDATE(), @ReceivedBy);

        IF @TranCounter = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranCounter = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK TRANSACTION; END
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION AddBatchSave;
        THROW;
    END CATCH
END
GO
