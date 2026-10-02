/* ================================================================
   2026-10-01f STS V2 alignment: rolled-back test (DEV only)
   ================================================================
   Run after 2026-10-01f_STS_V2_Alignment.sql. Read the PASS / FAIL lines
   in the Messages tab. Every part runs inside BEGIN TRAN ... ROLLBACK and
   the last check proves nothing was left behind.

   Set @PONumber (an APPROVED, unprocessed STS request nobody is working
   on; leave it NULL once to list candidates) and @User (a real user's
   full name, what the form sends as Login.Fullname). While a part runs
   it holds that request's lock and the picked lots, so pick a request
   nobody is processing.

   Part 1  scan / cancel / Save / cancel, every check on one transfer:
           - the lock taken is STSTRANSIT:<PO>, not the old STSV2_ name
           - FIFO and line VAT flag = the product's, even when the lot's
             flag differs (the lots are flipped inside the transaction)
           - nothing is posted before Save (no tickets)
           - after Save and after a cancel, head office In Transit = the
             cost of the live lots (Exception Center T01), tickets balance,
             no VAT In Transit tickets
           - stock goes out and comes back by the scanned qty
   Part 2  cancel on a received transfer          -> 59834
   Part 3  cancel after the branch's first receive call (real
           spu_PostSTSReceiveFromFIFO), before it is marked received -> 59834
   Part 4  new line on a received transfer        -> 59834
   Part 5  new line on a saved transfer           -> 59835
   Part 6  second delivery number for the transfer -> 59836
   Part 7  cancel while another line still holds stock it never gave back:
           the In Transit sync refuses (59605), and everything rolls back
   Parts 2-7 each end when the procedure itself rolls the transaction
   back, which is why they are separate.

   Manual two-session check (optional): in window 1 run
       BEGIN TRAN; <post a V2 line on the request>; EXEC sp_ConfirmBranchOrderSTS ...;
       WAITFOR DELAY '00:00:20'; ROLLBACK;
   and within those 20 seconds, in window 2,
       BEGIN TRAN; <post a V2 line on the same request>; ROLLBACK;
   Window 2 must wait for window 1, then finish. A 1205 deadlock is a FAIL.
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @Out NVARCHAR(4000);   -- PRINT cannot hold a subquery (1046), so each PASS/FAIL line is built here first

DECLARE @PONumber VARCHAR(10) = NULL;     -- required
DECLARE @User     VARCHAR(30) = NULL;     -- required: a real Login.Fullname
DECLARE @Origin   VARCHAR(10) = '888';
DECLARE @Qty      DECIMAL(18,3) = 1;

IF @PONumber IS NULL
BEGIN
    PRINT 'Set @PONumber. Candidates: fresh APPROVED requests with a non-combo product that has priced stock at ' + @Origin + ':';
    SELECT TOP (10) t.PONumber, t.InitiatingBranch, t.EffectivityDate, p.ProductCode, p.Description, p.Available
    FROM dbo.TransferOrderSummary AS t
    CROSS APPLY dbo.funcview_STSV2_Products(@Origin, t.PONumber) AS p
    WHERE t.Status = 'APPROVED' AND ISNULL(t.isProcess, 0) = 0 AND LEN(t.PONumber) <= 7
      AND p.IsCombo = 0 AND p.Available >= 3 * @Qty
      AND NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary AS d WHERE d.PONumber = t.PONumber)
      AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster AS tm WHERE tm.ReferenceKey = t.PONumber)
    ORDER BY t.PONumber;
    RETURN;
END
IF @User IS NULL
BEGIN
    PRINT 'Set @User to a real user''s full name (Login.Fullname).';
    RETURN;
END
IF dbo.func_getUsername(@User) IS NULL
    PRINT 'WARNING: dbo.func_getUsername(@User) is NULL; Save may fail on the ticket''s user. Use a real Login.Fullname.';

-- the request must be fresh
IF NOT EXISTS (SELECT 1 FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber AND Status = 'APPROVED' AND ISNULL(isProcess, 0) = 0)
   OR EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE PONumber = @PONumber)
   OR EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE PONumber = @PONumber)
   OR EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber)
   OR EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber)
BEGIN
    PRINT 'Request ' + @PONumber + ' is not fresh (needs APPROVED, not processed, no delivery, receipt or ticket yet).';
    RETURN;
END

-- product: non-combo, VAT flag set at the origin, enough stock, every eligible lot priced
DECLARE @Dest VARCHAR(10) = (SELECT InitiatingBranch FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber);
DECLARE @Product VARCHAR(10);
SELECT TOP (1) @Product = p.ProductCode
FROM dbo.funcview_STSV2_Products(@Origin, @PONumber) AS p
WHERE p.IsCombo = 0 AND p.Available >= 3 * @Qty
  AND EXISTS (SELECT 1 FROM dbo.Products AS pr WHERE pr.ProductCode = p.ProductCode AND pr.BranchCode = @Origin AND pr.isVat IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM dbo.fn_InvEligibleLots(@Origin) AS e
                  INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = e.SequenceNumber
                  WHERE e.Product = p.ProductCode AND ISNULL(i.Cost, 0) <= 0)
ORDER BY p.ProductCode;
IF @Product IS NULL
BEGIN
    PRINT 'Request ' + @PONumber + ' has no non-combo product with at least ' + CAST(3 * @Qty AS VARCHAR(20))
        + ' in priced stock at ' + @Origin + '. Pick another request.';
    RETURN;
END
DECLARE @ProdVat BIT = (SELECT TOP (1) CAST(isVat AS BIT) FROM dbo.Products WHERE ProductCode = @Product AND BranchCode = @Origin);

-- the product's lots as they are now (everything below must leave them exactly so)
IF OBJECT_ID('tempdb..#Lots') IS NOT NULL DROP TABLE #Lots;
SELECT e.SequenceNumber, i.Available AS Available0, ISNULL(i.IsVat, 0) AS IsVat0
INTO #Lots
FROM dbo.fn_InvEligibleLots(@Origin) AS e
INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = e.SequenceNumber
WHERE e.Product = @Product;
DECLARE @A0 DECIMAL(18,3) = (SELECT SUM(Available0) FROM #Lots);

-- a lot to scan by barcode (else the second line uses the batch method)
DECLARE @ScanBarcode VARCHAR(100), @Ship VARCHAR(10), @RefCode VARCHAR(100);
SELECT TOP (1) @ScanBarcode = e.Barcode
FROM dbo.fn_InvEligibleLots(@Origin) AS e
WHERE e.Product = @Product AND e.Available >= @Qty AND NULLIF(LTRIM(RTRIM(e.Barcode)), '') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.fn_InvEligibleLots(@Origin) AS o WHERE o.Barcode = e.Barcode AND o.SequenceNumber < e.SequenceNumber)
ORDER BY e.SequenceNumber DESC;
SELECT TOP (1) @Ship = ISNULL(e.ShipmentNo, ''), @RefCode = ISNULL(e.ReferenceCode, '')
FROM dbo.fn_InvEligibleLots(@Origin) AS e
WHERE e.Product = @Product AND e.Available >= @Qty
ORDER BY e.SequenceNumber;

-- delivery numbers nobody uses (only ever inside the rolled-back transactions)
DECLARE @DevN BIGINT = (SELECT MAX(n) FROM (SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) AS n FROM dbo.DeliverySummary
                                            UNION ALL SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) FROM dbo.DeliveryDetails
                                            UNION ALL SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) FROM dbo.InventoryDeliveryFIFO) AS x);
DECLARE @Dev VARCHAR(20) = CAST(@DevN + 1 AS VARCHAR(20)), @Dev2 VARCHAR(20) = CAST(@DevN + 2 AS VARCHAR(20));
IF LEN(@Dev2) > 7
BEGIN
    PRINT 'Generated delivery number ' + @Dev2 + ' is longer than 7 characters; set @Dev / @Dev2 by hand.';
    RETURN;
END

PRINT 'Request ' + @PONumber + ' -> branch ' + @Dest + ', product ' + @Product + ' (product isVat ' + CAST(@ProdVat AS VARCHAR(1))
    + '), deliveries ' + @Dev + ' / ' + @Dev2 + ', second line by ' + CASE WHEN @ScanBarcode IS NOT NULL THEN 'SCAN ' + @ScanBarcode ELSE 'BATCH' END;

-- shared checks
DECLARE @TransitSql NVARCHAR(MAX) = N'
    SELECT @Live = ISNULL(SUM(f.TotalCost), 0)          -- as Exception Center T01: every live FIFO row of the PO
    FROM dbo.InventoryDeliveryFIFO AS f
    WHERE f.PONumber = @PO AND f.isErrorCorrect = 0;
    SELECT @Posted = ISNULL(SUM(td.Debit - td.Credit), 0)
    FROM dbo.TicketMaster AS tm
    INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey = @PO AND tm.BranchCode = ''888''
      AND (tm.Mnemonic LIKE ''IT-HO-%'' OR tm.Mnemonic LIKE ''ITR-HO-%'')
      AND td.AccountCode IN (SELECT m.AccountCode FROM dbo.JournalEntryMapping AS m
                             WHERE m.Mnemonic IN (''IT-HO-VAT'', ''IT-HO-VATEX'') AND m.DebitCredit = ''D'' AND m.IsActive = 1);
    SELECT @Unbalanced = COUNT(*)
    FROM (SELECT tm.TicketNumber
          FROM dbo.TicketMaster AS tm
          INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
          WHERE tm.ReferenceKey = @PO
          GROUP BY tm.TicketNumber, tm.BranchCode
          HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005) AS x;
    SELECT @VatTickets = COUNT(*) FROM dbo.TicketMaster
    WHERE ReferenceKey = @PO AND Mnemonic IN (''IT-HO-VAT'', ''ITR-HO-VAT'');';
DECLARE @TransitParams NVARCHAR(400) = N'@PO VARCHAR(10), @Live DECIMAL(18,2) OUTPUT, @Posted DECIMAL(18,2) OUTPUT, @Unbalanced INT OUTPUT, @VatTickets INT OUTPUT';

DECLARE @Ref VARCHAR(10), @SeqA INT, @SeqB INT, @SeqC INT, @Bad INT, @AvailNow DECIMAL(18,3),
        @Live DECIMAL(18,2), @Posted DECIMAL(18,2), @Unbalanced INT, @VatTickets INT,
        @Err INT, @Msg NVARCHAR(2048), @Step VARCHAR(10);
DECLARE @RL dbo.tt_STSReceiveFIFOLines;

------------------------------------------------------------------
-- Part 1
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    -- give every lot the opposite VAT flag of the product, so the VAT checks prove something
    UPDATE i SET i.IsVat = CASE WHEN @ProdVat = 1 THEN 0 ELSE 1 END
    FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber;
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;

    -- 1a. line A, FIFO Auto
    SET @Step = '1a';
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqA = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);

    SELECT @Out = CASE WHEN APPLOCK_MODE('public', N'STSTRANSIT:' + @PONumber, 'Transaction') = 'Exclusive'
                AND APPLOCK_MODE('public', N'STSV2_' + @Dev + N'_' + @PONumber, 'Transaction') = 'NoLock'
               THEN 'PASS' ELSE 'FAIL' END + '  1a lock is STSTRANSIT:' + @PONumber + ' (old STSV2_ name not taken)';
    PRINT @Out;
    SELECT @Bad = COUNT(*) FROM dbo.InventoryDeliveryFIFO
    WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @SeqA AND ISNULL(isVat, 0) <> @ProdVat;
    SELECT @Out = CASE WHEN @Bad = 0 AND EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @SeqA)
               THEN 'PASS' ELSE 'FAIL' END + '  1a FIFO isVat = product flag although the lot flag differs';
    PRINT @Out;
    SELECT @Out = CASE WHEN EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @SeqA AND ISNULL(isVat, 0) = @ProdVat)
               THEN 'PASS' ELSE 'FAIL' END + '  1a line isVat = product flag';
    PRINT @Out;
    SELECT @Out = CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber)
               THEN 'PASS' ELSE 'FAIL' END + '  1a nothing posted before Save';
    PRINT @Out;
    SET @AvailNow = (SELECT SUM(i.Available) FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber);
    SELECT @Out = CASE WHEN @AvailNow = @A0 - @Qty THEN 'PASS' ELSE 'FAIL' END
          + '  1a stock out by the scanned qty (' + CAST(@A0 AS VARCHAR(30)) + ' -> ' + CAST(@AvailNow AS VARCHAR(30)) + ')';
    PRINT @Out;

    -- 1b. line B, by barcode when a lot has one (the method whose VAT order changed), else by batch
    SET @Step = '1b';
    IF @ScanBarcode IS NOT NULL
        EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
             @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'SCAN', @Qty = @Qty, @Barcode = @ScanBarcode;
    ELSE
        EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
             @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'BATCH', @Qty = @Qty, @ProductCode = @Product,
             @ShipmentNo = @Ship, @ReferenceCode = @RefCode;
    SET @SeqB = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    SELECT @Bad = COUNT(*) FROM dbo.InventoryDeliveryFIFO
    WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @SeqB AND ISNULL(isVat, 0) <> @ProdVat;
    SELECT @Out = CASE WHEN @Bad = 0 AND EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @SeqB AND ISNULL(isVat, 0) = @ProdVat)
               THEN 'PASS' ELSE 'FAIL' END + '  1b ' + CASE WHEN @ScanBarcode IS NOT NULL THEN 'SCAN' ELSE 'BATCH' END + ' line: line and FIFO isVat = product flag';
    PRINT @Out;

    -- 1c. cancel line B before Save: stock back, still nothing posted
    SET @Step = '1c';
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @SeqB, @OriginBranch = @Origin, @PreparedBy = @User;
    SET @AvailNow = (SELECT SUM(i.Available) FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber);
    SELECT @Out = CASE WHEN @AvailNow = @A0 - @Qty
                AND EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @SeqB AND isCancelled = 1)
                AND NOT EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @SeqB AND isErrorCorrect = 0)
               THEN 'PASS' ELSE 'FAIL' END + '  1c cancel before Save: line cancelled, stock back (' + CAST(@AvailNow AS VARCHAR(30)) + ')';
    PRINT @Out;
    SELECT @Out = CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber)
               THEN 'PASS' ELSE 'FAIL' END + '  1c cancel before Save posts nothing';
    PRINT @Out;

    -- 1d. line C, then Save
    SET @Step = '1d';
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqC = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    EXEC dbo.sp_ConfirmBranchOrderSTS @parmdevno = @Dev, @parmrefno = @Ref, @parmeffectivitydate = NULL, @parmpono = @PONumber,
         @parmbarcode = '', @parmbranchcode = @Dest, @parmorigin = @Origin, @preparedby = @User;
    EXEC sp_executesql @TransitSql, @TransitParams, @PO = @PONumber, @Live = @Live OUTPUT, @Posted = @Posted OUTPUT,
         @Unbalanced = @Unbalanced OUTPUT, @VatTickets = @VatTickets OUTPUT;
    SELECT @Out = CASE WHEN ABS(@Live - @Posted) < 0.01 AND @Live > 0 AND @Unbalanced = 0 AND @VatTickets = 0 THEN 'PASS' ELSE 'FAIL' END
          + '  1d after Save: In Transit ' + CAST(@Posted AS VARCHAR(30)) + ' = live lots ' + CAST(@Live AS VARCHAR(30))
          + ', unbalanced tickets ' + CAST(@Unbalanced AS VARCHAR(10)) + ', VAT tickets ' + CAST(@VatTickets AS VARCHAR(10));
    PRINT @Out;

    -- 1e. cancel line A after Save: In Transit follows the live lots (line C stays)
    SET @Step = '1e';
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @SeqA, @OriginBranch = @Origin, @PreparedBy = @User;
    EXEC sp_executesql @TransitSql, @TransitParams, @PO = @PONumber, @Live = @Live OUTPUT, @Posted = @Posted OUTPUT,
         @Unbalanced = @Unbalanced OUTPUT, @VatTickets = @VatTickets OUTPUT;
    SET @AvailNow = (SELECT SUM(i.Available) FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber);
    SELECT @Out = CASE WHEN ABS(@Live - @Posted) < 0.01 AND @Live > 0 AND @Unbalanced = 0 AND @VatTickets = 0 AND @AvailNow = @A0 - @Qty
               THEN 'PASS' ELSE 'FAIL' END
          + '  1e cancel after Save: In Transit ' + CAST(@Posted AS VARCHAR(30)) + ' = live lots ' + CAST(@Live AS VARCHAR(30))
          + ', stock ' + CAST(@AvailNow AS VARCHAR(30)) + ' (one line still out)';
    PRINT @Out;
    SELECT @Out = CASE WHEN EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber AND Mnemonic = 'ITR-HO-VATEX'
                                                         AND CAST(TicketDate AS DATE) = CAST(GETDATE() AS DATE))
               THEN 'PASS' ELSE 'FAIL' END + '  1e the reversal ticket is ITR-HO-VATEX dated today';
    PRINT @Out;
END TRY
BEGIN CATCH
    PRINT 'FAIL  Part 1 stopped at ' + ISNULL(@Step, '?') + ': ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' ' + ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- Parts 2-7: each must end in the expected error
------------------------------------------------------------------
-- Part 2: cancel on a received transfer
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqA = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    UPDATE dbo.DeliverySummary SET Status = 'DELIVERED' WHERE DeliveryNo = @Dev AND PONumber = @PONumber;
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @SeqA, @OriginBranch = @Origin, @PreparedBy = @User;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @Out = CASE WHEN @Err = 59834 THEN 'PASS' ELSE 'FAIL' END + '  2 cancel on a received transfer refused: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

-- Part 3: cancel after the branch's first receive call (not yet marked received)
SELECT @Err = NULL, @Msg = NULL;
DELETE FROM @RL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqA = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    EXEC dbo.sp_ConfirmBranchOrderSTS @parmdevno = @Dev, @parmrefno = @Ref, @parmeffectivitydate = NULL, @parmpono = @PONumber,
         @parmbarcode = '', @parmbranchcode = @Dest, @parmorigin = @Origin, @preparedby = @User;
    INSERT INTO @RL (SeqNo, DeliveryNo, ProductCode, Barcode, ActualQty, SellingPrice)
    SELECT SeqNo, DeliveryNo, ProductNo, ISNULL(BarcodeNo, ''), QtyDelivered, SellingPrice   -- AUTO lines have no barcode; the TVP column is NOT NULL
    FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @SeqA;
    EXEC dbo.spu_PostSTSReceiveFromFIFO @PONumber = @PONumber, @BranchCode = @Dest, @ReceivedBy = @User, @Lines = @RL;
    IF NOT EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber)
        PRINT 'NOTE  3: the receive call recorded nothing (see its skipped-lines result); the check below proves less.';
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @SeqA, @OriginBranch = @Origin, @PreparedBy = @User;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @Out = CASE WHEN @Err = 59834 THEN 'PASS' ELSE 'FAIL' END + '  3 cancel during receiving refused: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

-- Part 4: new line on a received transfer
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    UPDATE dbo.DeliverySummary SET Status = 'DELIVERED' WHERE DeliveryNo = @Dev AND PONumber = @PONumber;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @Out = CASE WHEN @Err = 59834 THEN 'PASS' ELSE 'FAIL' END + '  4 new line on a received transfer refused: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

-- Part 5: new line on a saved transfer
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    EXEC dbo.sp_ConfirmBranchOrderSTS @parmdevno = @Dev, @parmrefno = @Ref, @parmeffectivitydate = NULL, @parmpono = @PONumber,
         @parmbarcode = '', @parmbranchcode = @Dest, @parmorigin = @Origin, @preparedby = @User;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @Out = CASE WHEN @Err = 59835 THEN 'PASS' ELSE 'FAIL' END + '  5 new line on a saved transfer refused: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

-- Part 6: a second delivery number for the same transfer
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev2, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @Out = CASE WHEN @Err = 59836 THEN 'PASS' ELSE 'FAIL' END + '  6 second delivery for the transfer refused: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

-- Part 7: the In Transit sync refuses while a cancelled line still holds stock; nothing may stick
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqA = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SET @SeqC = (SELECT MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber);
    EXEC dbo.sp_ConfirmBranchOrderSTS @parmdevno = @Dev, @parmrefno = @Ref, @parmeffectivitydate = NULL, @parmpono = @PONumber,
         @parmbarcode = '', @parmbranchcode = @Dest, @parmorigin = @Origin, @preparedby = @User;
    -- line C "cancelled" without giving its stock back (what the old one-lot cancel bug left behind)
    UPDATE dbo.DeliveryDetails SET isCancelled = 1 WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @SeqC;
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @SeqA, @OriginBranch = @Origin, @PreparedBy = @User;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
DECLARE @TranAfter INT = @@TRANCOUNT;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET @AvailNow = (SELECT SUM(i.Available) FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber);
SELECT @Out = CASE WHEN @Err = 59605 AND @TranAfter = 0 AND @AvailNow = @A0 THEN 'PASS' ELSE 'FAIL' END
      + '  7 sync refusal surfaces as 59605 and rolls everything back (open transactions ' + CAST(@TranAfter AS VARCHAR(5))
      + ', stock ' + CAST(@AvailNow AS VARCHAR(30)) + '): ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');
PRINT @Out;

------------------------------------------------------------------
-- Nothing may remain
------------------------------------------------------------------
SELECT @Out = CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE DeliveryNo IN (@Dev, @Dev2) OR PONumber = @PONumber)
            AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo IN (@Dev, @Dev2) OR PONumber = @PONumber)
            AND NOT EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO WHERE DeliveryNo IN (@Dev, @Dev2) OR PONumber = @PONumber)
            AND NOT EXISTS (SELECT 1 FROM dbo.ReceivedOrderDetails WHERE PONumber = @PONumber)
            AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber)
            AND EXISTS (SELECT 1 FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber AND ISNULL(isProcess, 0) = 0)
            AND NOT EXISTS (SELECT 1 FROM dbo.Inventory AS i INNER JOIN #Lots AS l ON l.SequenceNumber = i.SequenceNumber
                            WHERE i.Available <> l.Available0 OR ISNULL(i.IsVat, 0) <> l.IsVat0)
           THEN 'PASS' ELSE 'FAIL' END + '  nothing left behind (request ' + @PONumber + ', deliveries ' + @Dev + ' / ' + @Dev2 + ', lots as before)';
PRINT @Out;
