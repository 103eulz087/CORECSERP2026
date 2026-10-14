/* ================================================================
   [80] 2026-10-14 - AR: reversal matches invoice rows by PO + customer; repair of the rows hit by invoice-no.-only matching
   ================================================================
   User 2026-10-14: "fix the X-009660 rows and trace the cause". Traced on PRODUCTION (read-only):
   - Cause 1 (fixed 2026-09-23 23:40, no code change here): sp_AddPaymentClient from 09-01 to 09-23 23:40 updated every
     TransactionChargeSales row with the payment's invoice no. (no PO, no customer). OR 30185 (keyed 09-23 15:03, paid PO
     4990 of X-009660) also put 5,070.00 paid on the returned POs 4913 / 4918 of the same invoice no.
   - Cause 2 (STILL LIVE until this script): sp_ReversePaymentClient matches the invoice rows by invoice no. alone.
       * 10-08 13:34: the reversal of OR 38494 (C-048113, PO 4753, 172,886.15) also took 172,886.15 off the returned row
         PO 4739 (total 0), which then showed 172,886.15 owed. The Edit screen pre-fills by invoice no. (first row = 4739),
         so the re-entered OR 38577 (13:35) was posted on 4739 and the real invoice 4753 still shows UNPAID 172,886.15.
       * 09-23 08:14: the reversal of OR 29577 (customer 00005717, E2608-01-A) put -653.00 paid on the cancelled row of
         customer 00001300 with the same invoice no.
     The client ledger and the GL are right in every case (only the invoice rows of the payment screen are wrong).
   1. sp_ReversePaymentClient: every invoice-row update matches InvoiceNo + PONumber = ReferenceNo + customer (as the
      posting proc). Needs [79] (guard: the [79] text by SHA-256). Backup _OLD_10142026210000.
   2. Data, each fix only when its rows are exactly as found on 10-14 (else listed as SKIPPED, nothing changed for it):
        F1 X-009660 / 00001147: POs 4913, 4918 (returned, total 0): paid 5,070.00 -> 0, balance -5,070.00 -> 0
        F2 C-048113 / 00001448 (PRODUCTION only): OR 38577's two C-048113 lines PO 4739 -> 4753 (its C-048076 lines are right); PO 4753 paid 0 -> 172,886.15,
           balance 0, FULLYPAID. PO 4739 stays 0 / 0
        F3 E2608-01-A / 00001300: PO 8117 (cancelled, total 0): paid -653.00 -> 0
      Backups Repair80_Backup_TCS_20261014 / Repair80_Backup_APD_20261014. No ledger, GL or bank row changes.
   C# (new exe): ClientPaymentsDevExAcctg's Edit pre-fill finds the row by invoice no. AND PO.
   One transaction; any failure rolls everything back.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 0. prerequisites -------------------------------------------------------------------------------------------------------------
IF CHARINDEX('[80]', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient'))) > 0
BEGIN
    RAISERROR('[80] already applied here; nothing to do.', 16, 1);
    SET NOEXEC ON;
END
-- the [79] text, compared without spaces / tabs / line breaks (a run from SSMS may store blank lines differently)
ELSE IF ISNULL(CONVERT(VARCHAR(66), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')),
            CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), ' ', '')), 1), '')
          <> '0x47BAF4CDFD9001949424CCC754D0B91ADE5940CBE57B7A8A5C2A8C7B350CF599'
     OR OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10142026210000') IS NOT NULL
     OR OBJECT_ID('dbo.Repair80_Backup_TCS_20261014') IS NOT NULL
     OR OBJECT_ID('dbo.Repair80_Backup_APD_20261014') IS NOT NULL
BEGIN
    RAISERROR('[80] stopped, nothing changed: sp_ReversePaymentClient is not the [79] version here (run [79] first), or a [80] backup already exists.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;
GO

EXEC sp_rename 'dbo.sp_ReversePaymentClient', 'sp_ReversePaymentClient_OLD_10142026210000';
GO

-- 1. sp_ReversePaymentClient ---------------------------------------------------------------------------------------------------

-- ============================================================
-- sp_ReversePaymentClient — sync Balance formula with SP above
--
-- Only change from previous version: Balance recalculation
-- now excludes OffsetAmount (matching Step 7 above).
-- All other reversal logic unchanged.
-- ============================================================
CREATE PROCEDURE [dbo].[sp_ReversePaymentClient]
    @PaymentHeaderID INT,
    @ReversedBy      VARCHAR(50)
AS
/*  [79] 2026-10-14: PayStatus keeps a balance-forward credit (negative TotalAmount) open when its use is reversed (it
    used to become FULLYPAID at Balance <= 0 and drop out of the payment list); a payment settled only with credits has
    no ticket, so no reversal ticket number is taken for it. Everything else unchanged.
    [80] 2026-10-14: the invoice rows are matched by invoice no. AND PO (ARPaymentDetails.PONumber = ReferenceNo) AND
    customer, like sp_AddPaymentClient since 2026-09-23. By invoice no. alone, a reversal also changed every other row
    with that invoice no. (a returned PO re-invoiced under the same no., or another customer's row): on PRODUCTION the
    10-08 reversal of 38494 made the returned row C-048113 / 4739 show 172,886.15 owed, and the 09-23 reversal of 29577
    (customer 00005717) put -653.00 paid on customer 00001300's row of E2608-01-A. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    -------------------------------------------------------
    -- 1. VALIDATE
    -------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM PaymentHeader WHERE PaymentHeaderID = @PaymentHeaderID
    )
    BEGIN
        ROLLBACK;
        THROW 60000, 'PaymentHeader not found.', 1;
    END

    IF EXISTS (
        SELECT 1 FROM PaymentHeader
        WHERE PaymentHeaderID = @PaymentHeaderID AND Status = 'REVERSED'
    )
    BEGIN
        ROLLBACK;
        THROW 60001, 'Transaction already reversed.', 1;
    END

    -------------------------------------------------------
    -- 2. LOAD HEADER
    -------------------------------------------------------
    DECLARE
        @custkey     CHAR(8),
        @refno       VARCHAR(20),
        @reversalRef VARCHAR(22),
        @paymentDate DATE,
        @remarks     VARCHAR(500);

    SELECT
        @custkey = CustomerKey,
        @refno   = ReferenceNo,
        @paymentDate = PaymentDate,
        @remarks = 'REVERSAL of ' + ReferenceNo
    FROM PaymentHeader
    WHERE PaymentHeaderID = @PaymentHeaderID;

    SET @reversalRef = LEFT(@refno + '-REV', 22);

    -------------------------------------------------------
    -- 3. REVERSE AmountPaid (net cash per invoice)
    -------------------------------------------------------
    UPDATE T
    SET T.AmountPaid = T.AmountPaid -
        (
            ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo AND D.PONumber = T.ReferenceNo
                      AND D.PaymentType = 'INVOICE PAYMENT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo AND D.PONumber = T.ReferenceNo
                      AND D.PaymentType = 'EWT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo AND D.PONumber = T.ReferenceNo
                      AND D.PaymentType = 'DISCOUNT'), 0)
          - ISNULL((SELECT SUM(D.Amount) FROM ARPaymentDetails D
                    WHERE D.PaymentHeaderID = @PaymentHeaderID
                      AND D.InvoiceNo = T.InvoiceNo AND D.PONumber = T.ReferenceNo
                      AND D.PaymentType = 'OFFSET'), 0)
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails D
        WHERE D.PaymentHeaderID = @PaymentHeaderID
          AND D.InvoiceNo = T.InvoiceNo AND D.PONumber = T.ReferenceNo AND T.CustomerKey = @custkey   -- [80]
          AND D.PaymentType = 'INVOICE PAYMENT'
    );

    -- Reverse EWT
    UPDATE T
    SET T.EWTAmount = ISNULL(T.EWTAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo AND T.ReferenceNo = P.PONumber AND T.CustomerKey = @custkey   -- [80]
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'EWT';

    -- Reverse Discount
    UPDATE T
    SET T.DiscountAmount = ISNULL(T.DiscountAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo AND T.ReferenceNo = P.PONumber AND T.CustomerKey = @custkey   -- [80]
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'DISCOUNT';

        -- Reverse Offset --Added By eulz
    UPDATE T
    SET T.OffsetAmount = ISNULL(T.OffsetAmount, 0) - P.Amount
    FROM TransactionChargeSales T
    JOIN ARPaymentDetails P ON T.InvoiceNo = P.InvoiceNo AND T.ReferenceNo = P.PONumber AND T.CustomerKey = @custkey   -- [80]
    WHERE P.PaymentHeaderID = @PaymentHeaderID
      AND P.PaymentType     = 'OFFSET';

    UPDATE ARPaymentDetails 
    SET ErrorTag=1
    WHERE PaymentHeaderID=@PaymentHeaderID

    -- NOTE: No reversal needed for OFFSET or OVERPAY on TCS
    -- (neither was written to TCS during posting)

    -------------------------------------------------------
    -- 4. RECALCULATE BALANCE (same formula as posting SP)
    -------------------------------------------------------
    UPDATE T
    SET T.Balance =
        T.TotalAmount - (
            ISNULL(T.AmountPaid,    0) +
            ISNULL(T.EWTAmount,     0) +
            ISNULL(T.DiscountAmount,0) + 
            ISNULL(T.OffsetAmount,0)        --Added by Eulz
        )
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails P
        WHERE P.PaymentHeaderID = @PaymentHeaderID
          AND P.InvoiceNo = T.InvoiceNo AND P.PONumber = T.ReferenceNo AND T.CustomerKey = @custkey   -- [80]
    );

    -------------------------------------------------------
    -- 5. UPDATE PAYSTATUS (same logic as posting SP)
    -------------------------------------------------------
    UPDATE T
    SET T.PayStatus =
        CASE
            WHEN T.Balance = 0 THEN 'FULLYPAID'
            -- [79] a balance-forward credit given back stays open
            WHEN T.TotalAmount < 0 THEN CASE WHEN ISNULL(T.AmountPaid, 0) <> 0 THEN 'PARTIAL' ELSE 'UNPAID' END
            WHEN T.Balance < 0 THEN 'FULLYPAID'
            WHEN T.AmountPaid    > 0
              OR T.EWTAmount     > 0
              OR T.DiscountAmount> 0 THEN 'PARTIAL'
            ELSE 'UNPAID'
        END
    FROM TransactionChargeSales T
    WHERE EXISTS (
        SELECT 1 FROM ARPaymentDetails P
        WHERE P.PaymentHeaderID = @PaymentHeaderID
          AND P.InvoiceNo = T.InvoiceNo AND P.PONumber = T.ReferenceNo AND T.CustomerKey = @custkey   -- [80]
    );

    -------------------------------------------------------
    -- 6. GET REVERSAL TICKET NUMBER
    -------------------------------------------------------
    DECLARE @ReversalTicketNo BIGINT;
    IF EXISTS (SELECT 1 FROM TicketMaster WHERE ReferenceNumber = @refno)   -- [79] credits-only payments have no ticket
        EXEC GetTicketNumber @ReversalTicketNo OUTPUT;

    -------------------------------------------------------
    -- 7. REVERSAL TICKET MASTER
    -------------------------------------------------------
    INSERT INTO TicketMaster
    (
        TicketDate, SupplementaryNumber, BranchCode, Origin,
        TicketNumber, ReferenceNumber, ReferenceKey,
        Owner, Particulars, EnteredBy,
        CheckedBy, ApprovedBy, Status, Mnemonic, Product
    )
    SELECT
        @paymentDate, 0, '888', '888',
        @ReversalTicketNo, @refno, TM.ReferenceKey,
        TM.Owner, 'REVERSAL: ' + TM.Particulars,
        @ReversedBy, '*', '*', 'REVERSED', NULL, @remarks
    FROM TicketMaster TM
    WHERE TM.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 8. REVERSE TICKET DETAILS (swap DR/CR)
    -------------------------------------------------------
    INSERT INTO TicketDetails
    (
        TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
        TicketNumber, ReferenceNumber,
        AccountCode, Debit, Credit, CostCenter
    )
    SELECT
        @paymentDate, 0, TD.BranchCode, TD.ReferenceKey,
        @ReversalTicketNo, @refno,
        TD.AccountCode,
        TD.Credit,  -- swapped
        TD.Debit,   -- swapped
        TD.CostCenter
    FROM TicketDetails TD
    WHERE TD.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 9. REVERSE CLIENT LEDGER --SELECT * FROM ClientLedger
    -------------------------------------------------------
    INSERT INTO ClientLedger
    (
        TRN_SEQ_NO, AccountKey, AccountID,
        PostingDate, InitiatingBranch, Description,
        TransCode, TransactionDate,
        ReferenceNumber, ReferenceKey, InvoiceNo,
        Debit, Credit, BeginningBalance, EndingBalance,
        ORNumber, TransactedBy, ApprovedBy,
        Remarks, TotalAmount, ErrorCorrectTag, TicketReference
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY CL.InvoiceNo)
          + ISNULL((SELECT MAX(TRN_SEQ_NO) FROM ClientLedger WHERE AccountKey = @custkey), 0),
        CL.AccountKey, CL.AccountID,
        GETDATE(), CL.InitiatingBranch, @remarks,
        CL.TransCode, CL.TransactionDate,   -- 2026-10-09c: the reversed row's date (was the reversal day)
        @refno, CL.ReferenceKey, CL.InvoiceNo,
        CL.Credit, CL.Debit,  -- swapped
        0, 0,
        CL.ORNumber, @ReversedBy, '*',
        'REVERSAL ENTRY',
        CL.TotalAmount * -1, 0,
        @ReversalTicketNo
    FROM ClientLedger CL
    WHERE CL.ReferenceNumber = @refno;

    -------------------------------------------------------
    -- 10. MARK HEADER AS REVERSED
    -------------------------------------------------------
    UPDATE PaymentHeader
    SET Status       = 'REVERSED',
        ReversedBy   = @ReversedBy,
        ReversedDate = GETDATE()
    WHERE PaymentHeaderID = @PaymentHeaderID;

    -------------------------------------------------------
    -- 11. FLAG PAYMENT METHOD TABLES
    -------------------------------------------------------
    UPDATE TransactionCashCollection
    SET isErrorCorrect = 1
    WHERE PaymentHeaderID = @PaymentHeaderID;

    UPDATE TransactionCheque
    SET Remarks = 'REVERSED'
    WHERE PaymentHeaderID = @PaymentHeaderID;

    UPDATE TransactionOnline
    SET Remarks = 'REVERSED'
    WHERE PaymentHeaderID = @PaymentHeaderID;

    --UPDATE TransactionCreditCard
    --SET Remarks = 'REVERSED'
    --WHERE PaymentHeaderID = @PaymentHeaderID;

    -------------------------------------------------------
    -- 12. VOID DIT IN BANK RECON
    --
    -- Matches by SourceRef + SourceModule — works correctly
    -- regardless of HeaderID since SourceRef = @refno is unique.
    -- ResolvedReason = 'REVERSED' for audit trail.
    -------------------------------------------------------
    UPDATE BankStatementRecon
    SET IsResolved     = 1,
        ResolvedDate   = GETDATE(),
        ResolvedReason = 'REVERSED'
    WHERE SourceRef    = @refno
      AND SourceModule = 'AR-PAYMENT'
      AND ItemType     = 'DIT'
      AND IsResolved   = 0;

    -------------------------------------------------------
    COMMIT;
END

GO

-- 2. data -----------------------------------------------------------------------------------------------------------------------
BEGIN TRY
    DECLARE @Res TABLE (Fix VARCHAR(4), Result VARCHAR(10), Detail VARCHAR(300));

    SELECT t.*, CAST(GETDATE() AS DATETIME) AS BackupAt
    INTO dbo.Repair80_Backup_TCS_20261014
    FROM dbo.TransactionChargeSales AS t
    WHERE (t.CustomerKey = '00001147' AND t.InvoiceNo = 'X-009660')
       OR (t.CustomerKey = '00001448' AND t.InvoiceNo = 'C-048113')
       OR (t.CustomerKey = '00001300' AND t.InvoiceNo = 'E2608-01-A');

    SELECT d.*, CAST(GETDATE() AS DATETIME) AS BackupAt
    INTO dbo.Repair80_Backup_APD_20261014
    FROM dbo.ARPaymentDetails AS d
    WHERE d.CustomerKey = '00001448' AND d.InvoiceNo = 'C-048113';

    -- F1 X-009660: the two returned POs carry OR 30185's 5,070.00
    IF (SELECT COUNT(*) FROM dbo.TransactionChargeSales
        WHERE CustomerKey = '00001147' AND InvoiceNo = 'X-009660' AND ReferenceNo IN ('4913', '4918')
          AND TotalAmount = 0 AND AmountPaid = 5070.00 AND Balance = -5070.00
          AND ISNULL(EWTAmount, 0) = 0 AND ISNULL(DiscountAmount, 0) = 0 AND ISNULL(OffsetAmount, 0) = 0) = 2
       AND EXISTS (SELECT 1 FROM dbo.TransactionChargeSales
                   WHERE CustomerKey = '00001147' AND InvoiceNo = 'X-009660' AND ReferenceNo = '4990'
                     AND TotalAmount = 5070.00 AND AmountPaid = 5070.00 AND Balance = 0)
       AND NOT EXISTS (SELECT 1 FROM dbo.ARPaymentDetails AS d JOIN dbo.PaymentHeader AS ph ON ph.PaymentHeaderID = d.PaymentHeaderID
                       WHERE d.CustomerKey = '00001147' AND d.InvoiceNo = 'X-009660' AND d.PONumber IN ('4913', '4918')
                         AND ISNULL(ph.Status, '') <> 'REVERSED')
    BEGIN
        UPDATE dbo.TransactionChargeSales
        SET AmountPaid = 0, Balance = 0, PayStatus = 'FULLYPAID'
        WHERE CustomerKey = '00001147' AND InvoiceNo = 'X-009660' AND ReferenceNo IN ('4913', '4918') AND AmountPaid = 5070.00;
        IF @@ROWCOUNT <> 2 THROW 59986, '[80] F1 expected 2 rows.', 1;
        INSERT INTO @Res VALUES ('F1', 'FIXED', 'X-009660 POs 4913 / 4918: paid 5,070.00 -> 0, balance -5,070.00 -> 0');
    END
    ELSE
        INSERT INTO @Res VALUES ('F1', 'SKIPPED', 'X-009660 rows not as found on 2026-10-14');

    -- F2 C-048113: OR 38577 sits on the returned PO 4739; the real invoice PO 4753 shows unpaid
    IF EXISTS (SELECT 1 FROM dbo.PaymentHeader WHERE PaymentHeaderID = 10054 AND ReferenceNo = '38577' AND CustomerKey = '00001448' AND ISNULL(Status, '') <> 'REVERSED')
       AND (SELECT COUNT(*) FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = 10054 AND InvoiceNo = 'C-048113' AND PONumber = '4739'
              AND ((PaymentType = 'INVOICE PAYMENT' AND Amount = 172886.15) OR (PaymentType = 'SERVICES' AND Amount = 2319.00))) = 2
       AND (SELECT COUNT(*) FROM dbo.ARPaymentDetails WHERE PaymentHeaderID = 10054 AND InvoiceNo = 'C-048113') = 2   -- (OR 38577 also paid C-048076 / PO 4672 correctly: left alone)
       AND EXISTS (SELECT 1 FROM dbo.TransactionChargeSales WHERE CustomerKey = '00001448' AND InvoiceNo = 'C-048113' AND ReferenceNo = '4753'
                     AND TotalAmount = 172886.15 AND AmountPaid = 0 AND Balance = 172886.15 AND PayStatus = 'UNPAID'
                     AND ISNULL(EWTAmount, 0) = 0 AND ISNULL(DiscountAmount, 0) = 0 AND ISNULL(OffsetAmount, 0) = 0)
       AND EXISTS (SELECT 1 FROM dbo.TransactionChargeSales WHERE CustomerKey = '00001448' AND InvoiceNo = 'C-048113' AND ReferenceNo = '4739'
                     AND TotalAmount = 0 AND AmountPaid = 0 AND Balance = 0)
       AND NOT EXISTS (SELECT 1 FROM dbo.ARPaymentDetails AS d JOIN dbo.PaymentHeader AS ph ON ph.PaymentHeaderID = d.PaymentHeaderID
                       WHERE d.CustomerKey = '00001448' AND d.InvoiceNo = 'C-048113' AND d.PONumber = '4753' AND ISNULL(ph.Status, '') <> 'REVERSED')
    BEGIN
        UPDATE dbo.ARPaymentDetails SET PONumber = '4753' WHERE PaymentHeaderID = 10054 AND InvoiceNo = 'C-048113' AND PONumber = '4739';
        IF @@ROWCOUNT <> 2 THROW 59986, '[80] F2 expected 2 payment lines.', 1;
        UPDATE dbo.TransactionChargeSales
        SET AmountPaid = 172886.15, Balance = 0, PayStatus = 'FULLYPAID'
        WHERE CustomerKey = '00001448' AND InvoiceNo = 'C-048113' AND ReferenceNo = '4753' AND AmountPaid = 0;
        IF @@ROWCOUNT <> 1 THROW 59986, '[80] F2 expected 1 invoice row.', 1;
        INSERT INTO @Res VALUES ('F2', 'FIXED', 'C-048113: OR 38577 moved from returned PO 4739 to PO 4753; PO 4753 paid 172,886.15, balance 0');
    END
    ELSE
        INSERT INTO @Res VALUES ('F2', 'SKIPPED', 'C-048113 / OR 38577 not as found on PRODUCTION 2026-10-14 (expected on DEV / STAGING)');

    -- F3 E2608-01-A: another customer's reversal left -653.00 paid on this cancelled row
    IF EXISTS (SELECT 1 FROM dbo.TransactionChargeSales WHERE CustomerKey = '00001300' AND InvoiceNo = 'E2608-01-A' AND ReferenceNo = '8117'
                 AND TotalAmount = 0 AND AmountPaid = -653.00 AND Balance = 0 AND PayStatus = 'CANCELLED')
    BEGIN
        UPDATE dbo.TransactionChargeSales SET AmountPaid = 0
        WHERE CustomerKey = '00001300' AND InvoiceNo = 'E2608-01-A' AND ReferenceNo = '8117' AND AmountPaid = -653.00;
        IF @@ROWCOUNT <> 1 THROW 59986, '[80] F3 expected 1 row.', 1;
        INSERT INTO @Res VALUES ('F3', 'FIXED', 'E2608-01-A / 00001300 PO 8117 (cancelled): paid -653.00 -> 0');
    END
    ELSE
        INSERT INTO @Res VALUES ('F3', 'SKIPPED', 'E2608-01-A row not as found on 2026-10-14');

    SELECT Fix, Result, Detail FROM @Res ORDER BY Fix;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @em NVARCHAR(2048) = N'[80] stopped, nothing changed: ' + ERROR_MESSAGE();
    RAISERROR(@em, 16, 1);
    SET NOEXEC ON;
END CATCH
GO

-- post-check: the new proc carries [80]; no row of the three invoices is left with a paid amount on a zero total, and the
-- real C-048113 invoice is not left unpaid while OR 38577 stands
IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_ReversePaymentClient')) NOT LIKE '%[[]80]%'
   OR OBJECT_ID('dbo.sp_ReversePaymentClient_OLD_10142026210000') IS NULL
   OR EXISTS (SELECT 1 FROM dbo.TransactionChargeSales
              WHERE ((CustomerKey = '00001147' AND InvoiceNo = 'X-009660') OR (CustomerKey = '00001300' AND InvoiceNo = 'E2608-01-A'))
                AND TotalAmount = 0 AND AmountPaid <> 0)
   OR (EXISTS (SELECT 1 FROM dbo.PaymentHeader WHERE PaymentHeaderID = 10054 AND ReferenceNo = '38577' AND ISNULL(Status, '') <> 'REVERSED')
       AND EXISTS (SELECT 1 FROM dbo.TransactionChargeSales WHERE CustomerKey = '00001448' AND InvoiceNo = 'C-048113' AND ReferenceNo = '4753' AND Balance <> 0))
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('[80] post-check failed; nothing changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
SELECT CustomerKey, InvoiceNo, ReferenceNo, TotalAmount, AmountPaid, Balance, PayStatus FROM dbo.TransactionChargeSales
WHERE InvoiceNo IN ('X-009660', 'C-048113', 'E2608-01-A') ORDER BY InvoiceNo, ReferenceNo;
SELECT name, CONVERT(VARCHAR(16), modify_date, 120) AS Modified FROM sys.objects
WHERE name IN ('sp_ReversePaymentClient', 'sp_ReversePaymentClient_OLD_10142026210000', 'Repair80_Backup_TCS_20261014', 'Repair80_Backup_APD_20261014') ORDER BY name;
GO
