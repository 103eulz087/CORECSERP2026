/* ================================================================
   2026-10-01f STS V2 alignment: rolled-back test (DEV only)
   ================================================================
   Run after 2026-10-01f_STS_V2_Alignment.sql. Every part runs inside
   BEGIN TRAN ... ROLLBACK and ends by checking that no test rows remain.
   Read the PASS / FAIL lines in the Messages tab.

   It picks a fresh STS request (APPROVED, not processed, no delivery or
   tickets yet) with a non-combo product in stock at @Origin, unless
   @PONumber is set. Nothing is kept.

   Part 1: post a line (AUTO) -> Save -> post a second line after Save ->
           cancel the first line. After each step head office's In
           Transit for the PO must equal the cost of its live lots (as
           Exception Center T01), and the FIFO / line VAT flag must be
           the product's.
   Part 2: cancel a line of a received transfer -> must fail with 59834.
   Part 3: post a line to a received transfer   -> must fail with 59834.
   (Parts 2 and 3 end when the procedure rolls everything back, which
   is why they are separate.)
   ================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @PONumber VARCHAR(10) = NULL;     -- set to test a specific request
DECLARE @Origin   VARCHAR(10) = '888';
DECLARE @User     VARCHAR(30) = 'TEST-10-01f';
DECLARE @Qty      DECIMAL(18,3) = 1;

-- In Transit accounts, from the mapping (as spu_STS_SyncInTransit)
DECLARE @TransitVat   VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VAT'   AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);
DECLARE @TransitVatEx VARCHAR(50) = (SELECT TOP 1 AccountCode FROM dbo.JournalEntryMapping WHERE Mnemonic = 'IT-HO-VATEX' AND DebitCredit = 'D' AND IsActive = 1 ORDER BY Seq);

-- pick the request and product
DECLARE @Dest VARCHAR(10), @Product VARCHAR(10), @Avail DECIMAL(18,3);
SELECT TOP (1) @PONumber = t.PONumber, @Dest = t.InitiatingBranch, @Product = p.ProductCode, @Avail = p.Available
FROM dbo.TransferOrderSummary AS t
CROSS APPLY dbo.funcview_STSV2_Products(@Origin, t.PONumber) AS p
WHERE (@PONumber IS NULL OR t.PONumber = @PONumber)
  AND t.Status = 'APPROVED' AND ISNULL(t.isProcess, 0) = 0
  AND LEN(t.PONumber) <= 7
  AND p.IsCombo = 0 AND p.Available >= 2 * @Qty
  AND EXISTS (SELECT 1 FROM dbo.Products AS pr WHERE pr.ProductCode = p.ProductCode AND pr.BranchCode = @Origin AND pr.isVat IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary AS d WHERE d.PONumber = t.PONumber)
  AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails AS d WHERE d.PONumber = t.PONumber)
  AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster AS tm WHERE tm.ReferenceKey = t.PONumber)
ORDER BY t.PONumber DESC;

IF @Product IS NULL
BEGIN
    PRINT 'No suitable request found (fresh, APPROVED, non-combo product with stock at ' + @Origin + '). Set @PONumber.';
    RETURN;
END

-- a delivery number nobody uses (only inside the rolled-back transaction)
DECLARE @Dev VARCHAR(20) = CAST(
    (SELECT MAX(n) FROM (SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) AS n FROM dbo.DeliverySummary
                         UNION ALL SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) FROM dbo.DeliveryDetails
                         UNION ALL SELECT MAX(TRY_CAST(DeliveryNo AS BIGINT)) FROM dbo.InventoryDeliveryFIFO) AS x) + 1 AS VARCHAR(20));
IF LEN(@Dev) > 7
BEGIN
    PRINT 'Generated delivery number ' + @Dev + ' is longer than 7 characters; set one by hand.';
    RETURN;
END

DECLARE @ProdVat BIT = (SELECT TOP 1 CAST(isVat AS BIT) FROM dbo.Products WHERE ProductCode = @Product AND BranchCode = @Origin);
PRINT 'Request ' + @PONumber + ' -> branch ' + @Dest + ', product ' + @Product + ' (isVat ' + CAST(@ProdVat AS VARCHAR(1)) + '), delivery ' + @Dev;

DECLARE @Ref VARCHAR(10), @Seq1 INT, @Seq2 INT, @Live DECIMAL(18,2), @Posted DECIMAL(18,2), @Bad INT, @Err INT, @Msg NVARCHAR(2048);

------------------------------------------------------------------
-- Part 1
------------------------------------------------------------------
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;

    -- 1a. first line
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SELECT @Seq1 = MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber;

    SELECT @Bad = COUNT(*) FROM dbo.InventoryDeliveryFIFO
    WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @Seq1 AND ISNULL(isVat, 0) <> ISNULL(@ProdVat, 0);
    PRINT CASE WHEN @Bad = 0 THEN 'PASS' ELSE 'FAIL' END + '  1a FIFO isVat = product flag (' + CAST(@Bad AS VARCHAR(10)) + ' rows differ)';

    SELECT @Bad = COUNT(*) FROM dbo.DeliveryDetails
    WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @Seq1 AND ISNULL(isVat, 0) <> ISNULL(@ProdVat, 0);
    PRINT CASE WHEN @Bad = 0 THEN 'PASS' ELSE 'FAIL' END + '  1a line isVat = product flag';

    -- 1b. Save
    EXEC dbo.sp_ConfirmBranchOrderSTS @parmdevno = @Dev, @parmrefno = @Ref, @parmeffectivitydate = NULL, @parmpono = @PONumber,
         @parmbarcode = '', @parmbranchcode = @Dest, @parmorigin = @Origin, @preparedby = @User;

    -- In Transit check (same as Exception Center T01)
    SELECT @Live = ISNULL(SUM(f.TotalCost), 0) FROM dbo.InventoryDeliveryFIFO AS f
    WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails AS dd WHERE dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber
                      AND dd.SeqNo = f.DevDetSeqNo AND (dd.isCancelled = 1 OR dd.isReturned = 1));
    SELECT @Posted = ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster AS tm
    INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey = @PONumber AND tm.BranchCode = '888' AND td.AccountCode IN (@TransitVat, @TransitVatEx)
      AND (tm.Mnemonic LIKE 'IT-HO-%' OR tm.Mnemonic LIKE 'ITR-HO-%');
    PRINT CASE WHEN ABS(@Live - @Posted) < 0.01 THEN 'PASS' ELSE 'FAIL' END
          + '  1b after Save: In Transit ' + CAST(@Posted AS VARCHAR(30)) + ' = live lots ' + CAST(@Live AS VARCHAR(30));
    IF @Live = 0
        PRINT 'NOTE  the picked lot costs 0 (e.g. a conversion lot), so the In Transit checks prove little; set @PONumber to another request.';

    -- 1c. a second line after Save keeps In Transit in step
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SELECT @Seq2 = MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber;

    SELECT @Live = ISNULL(SUM(f.TotalCost), 0) FROM dbo.InventoryDeliveryFIFO AS f
    WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails AS dd WHERE dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber
                      AND dd.SeqNo = f.DevDetSeqNo AND (dd.isCancelled = 1 OR dd.isReturned = 1));
    SELECT @Posted = ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster AS tm
    INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey = @PONumber AND tm.BranchCode = '888' AND td.AccountCode IN (@TransitVat, @TransitVatEx)
      AND (tm.Mnemonic LIKE 'IT-HO-%' OR tm.Mnemonic LIKE 'ITR-HO-%');
    PRINT CASE WHEN ABS(@Live - @Posted) < 0.01 THEN 'PASS' ELSE 'FAIL' END
          + '  1c line after Save: In Transit ' + CAST(@Posted AS VARCHAR(30)) + ' = live lots ' + CAST(@Live AS VARCHAR(30));

    -- 1d. cancel the first line
    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @Seq1, @OriginBranch = @Origin, @PreparedBy = @User;

    SELECT @Bad = COUNT(*) FROM dbo.InventoryDeliveryFIFO
    WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND DevDetSeqNo = @Seq1 AND isErrorCorrect = 0;
    PRINT CASE WHEN @Bad = 0 AND EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber AND SeqNo = @Seq1 AND isCancelled = 1)
               THEN 'PASS' ELSE 'FAIL' END + '  1d line cancelled, its lots restored';

    SELECT @Live = ISNULL(SUM(f.TotalCost), 0) FROM dbo.InventoryDeliveryFIFO AS f
    WHERE f.PONumber = @PONumber AND f.isErrorCorrect = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails AS dd WHERE dd.DeliveryNo = f.DeliveryNo AND dd.PONumber = f.PONumber
                      AND dd.SeqNo = f.DevDetSeqNo AND (dd.isCancelled = 1 OR dd.isReturned = 1));
    SELECT @Posted = ISNULL(SUM(td.Debit - td.Credit), 0) FROM dbo.TicketMaster AS tm
    INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
    WHERE tm.ReferenceKey = @PONumber AND tm.BranchCode = '888' AND td.AccountCode IN (@TransitVat, @TransitVatEx)
      AND (tm.Mnemonic LIKE 'IT-HO-%' OR tm.Mnemonic LIKE 'ITR-HO-%');
    PRINT CASE WHEN ABS(@Live - @Posted) < 0.01 THEN 'PASS' ELSE 'FAIL' END
          + '  1d after cancel: In Transit ' + CAST(@Posted AS VARCHAR(30)) + ' = live lots ' + CAST(@Live AS VARCHAR(30));

    PRINT CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber AND Mnemonic IN ('IT-HO-VAT', 'ITR-HO-VAT'))
               THEN 'PASS' ELSE 'FAIL' END + '  no VAT In Transit tickets (GL all VAT-exempt)';

    SELECT @Bad = COUNT(*)
    FROM (SELECT tm.TicketNumber
          FROM dbo.TicketMaster AS tm
          INNER JOIN dbo.TicketDetails AS td ON td.TicketNumber = tm.TicketNumber AND td.BranchCode = tm.BranchCode
          WHERE tm.ReferenceKey = @PONumber
          GROUP BY tm.TicketNumber, tm.BranchCode
          HAVING ABS(SUM(td.Debit) - SUM(td.Credit)) > 0.005) AS x;
    PRINT CASE WHEN @Bad = 0 THEN 'PASS' ELSE 'FAIL' END + '  every ticket of the request balances';
END TRY
BEGIN CATCH
    PRINT 'FAIL  Part 1 stopped: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' ' + ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

------------------------------------------------------------------
-- Part 2: cancel on a received transfer must fail (59834)
------------------------------------------------------------------
SET @Err = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.GetReferenceNumber @Ref OUTPUT;
    EXEC dbo.spu_PostSTSLineV2 @DeliveryNo = @Dev, @RefNo = @Ref, @PONumber = @PONumber, @DestinationBranch = @Dest,
         @OriginBranch = @Origin, @PreparedBy = @User, @Method = 'AUTO', @Qty = @Qty, @ProductCode = @Product;
    SELECT @Seq1 = MAX(CAST(SeqNo AS INT)) FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev AND PONumber = @PONumber;
    UPDATE dbo.DeliverySummary SET Status = 'DELIVERED' WHERE DeliveryNo = @Dev AND PONumber = @PONumber;

    EXEC dbo.spu_ReverseSTSLineV2 @DeliveryNo = @Dev, @PONumber = @PONumber, @SeqNo = @Seq1, @OriginBranch = @Origin, @PreparedBy = @User;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
PRINT CASE WHEN @Err = 59834 OR @Msg LIKE '%already been received%' THEN 'PASS' ELSE 'FAIL' END
      + '  2 cancel refused once received: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');

------------------------------------------------------------------
-- Part 3: a new line on a received transfer must fail (59834)
------------------------------------------------------------------
SET @Err = NULL; SET @Msg = NULL;
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
PRINT CASE WHEN @Err = 59834 OR @Msg LIKE '%already been received%' THEN 'PASS' ELSE 'FAIL' END
      + '  3 new line refused once received: ' + ISNULL(CAST(@Err AS VARCHAR(10)) + ' ' + @Msg, 'no error');

------------------------------------------------------------------
-- Nothing may remain
------------------------------------------------------------------
PRINT CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.DeliverySummary WHERE DeliveryNo = @Dev)
            AND NOT EXISTS (SELECT 1 FROM dbo.DeliveryDetails WHERE DeliveryNo = @Dev)
            AND NOT EXISTS (SELECT 1 FROM dbo.InventoryDeliveryFIFO WHERE DeliveryNo = @Dev)
            AND NOT EXISTS (SELECT 1 FROM dbo.TicketMaster WHERE ReferenceKey = @PONumber)
            AND EXISTS (SELECT 1 FROM dbo.TransferOrderSummary WHERE PONumber = @PONumber AND ISNULL(isProcess, 0) = 0)
           THEN 'PASS' ELSE 'FAIL' END + '  nothing left behind (delivery ' + @Dev + ', request ' + @PONumber + ')';
