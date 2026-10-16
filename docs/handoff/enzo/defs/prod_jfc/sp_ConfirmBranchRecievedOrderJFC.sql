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

        -- 2026-10-03: a line can have several receipt rows (one per batch), and scanned lines can
        -- share one lot barcode: the rows of a barcode are added up and fill its lines in SeqNo
        -- order (a short comes off the last line). Lines with no receipt row are left as they are.
        ;WITH L AS (
            SELECT dt.SeqNo, dt.DeliveryNo, dt.QtyDelivered, r.Qty AS RcvTotal,
                   ISNULL(SUM(dt.QtyDelivered) OVER (PARTITION BY dt.DeliveryNo, dt.BarcodeNo, dt.ProductNo ORDER BY dt.SeqNo
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS CumBefore,
                   ROW_NUMBER() OVER (PARTITION BY dt.DeliveryNo, dt.BarcodeNo, dt.ProductNo ORDER BY dt.SeqNo DESC) AS RevNo
            FROM DeliveryDetails dt
            CROSS APPLY (SELECT SUM(rt.Qty) AS Qty FROM ReceivedOrderDetails rt
                         WHERE rt.PONumber = dt.PONumber AND rt.Barcode = dt.BarcodeNo AND rt.ProductCode = dt.ProductNo) r
            WHERE dt.PONumber = @parmpono AND dt.isCancelled = 0 AND dt.isReturned = 0 AND r.Qty IS NOT NULL)
        UPDATE dt
        SET dt.Status = 'DELIVERED',
            dt.ActualQty = a.Qty,
            dt.Variance = (dt.QtyDelivered - a.Qty)
        FROM DeliveryDetails dt
        INNER JOIN (SELECT SeqNo, DeliveryNo,
                           CAST(CASE WHEN RevNo = 1 THEN CASE WHEN RcvTotal - CumBefore > 0 THEN RcvTotal - CumBefore ELSE 0 END
                                     WHEN RcvTotal - CumBefore >= QtyDelivered THEN QtyDelivered
                                     WHEN RcvTotal - CumBefore > 0 THEN RcvTotal - CumBefore
                                     ELSE 0 END AS DECIMAL(18,3)) AS Qty
                    FROM L) a ON a.SeqNo = dt.SeqNo AND a.DeliveryNo = dt.DeliveryNo
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
        SET TotalItem = (SELECT COUNT(*) FROM DeliveryDetails dl                       -- 2026-10-03: lines received, not receipt rows
                         WHERE dl.PONumber = @parmpono AND dl.isCancelled = 0 AND dl.isReturned = 0
                           AND EXISTS (SELECT 1 FROM ReceivedOrderDetails rx
                                       WHERE rx.PONumber = dl.PONumber AND rx.Barcode = dl.BarcodeNo AND rx.ProductCode = dl.ProductNo)),
            TotalKilo = (SELECT ISNULL(SUM(Qty), 0) FROM ReceivedOrderDetails WITH (NOLOCK) WHERE PONumber = @parmpono)
        WHERE PONumber = @parmpono;

        DECLARE @rcvVat MONEY, @rcvVatEx MONEY;
        SELECT @rcvVat   = 0,   -- 2026-10-01: the GL is all VAT-exempt (client rule)
               @rcvVatEx = ISNULL(SUM(ROUND(Qty * Cost, 2)), 0)
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
        SELECT @shipVat   = 0,
               @shipVatEx = ISNULL(SUM(f.TotalCost), 0)
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
