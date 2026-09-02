-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-02
-- Description: Fixes three blockers the sp-reviewer found in
--              spu_FinalizeConversionBarcode / spu_ReverseConversionBarcode
--              (2026-09-02_ConversionPerBarcode_ForPostingAndGL.sql):
--
--  [1] GL account codes were hardcoded in the SP body instead of driven by
--      dbo.JournalEntryMapping, the established convention every other
--      GL-posting change in this codebase follows (ClientPayment,
--      CreditMemo, ReturnSalesOrder, the existing IT-HO-VAT/IT-HO-VATEX
--      Inventory Transfer mnemonics). Fixed by adding a new Origin='IT'
--      Mnemonic='CONV-FINALIZE' with 8 rows (4 AmountTypes -- SOURCE_VAT/
--      SOURCE_VATEX/OUTPUT_VAT/OUTPUT_VATEX -- each posted once as Debit and
--      once as Credit, since a single conversion can have BOTH VAT and
--      VAT-exempt amounts on BOTH the source and output side
--      simultaneously, unlike the existing IT-HO-VAT/IT-HO-VATEX mnemonics
--      which assume a transfer is wholly one or the other).
--
--  [2] TOCTOU race: Finalize and Reverse both read Status via an unlocked
--      SELECT/EXISTS before BEGIN TRANSACTION and never re-checked it on
--      their terminal write, so two concurrent calls (double-click, two
--      users, a retry) could both pass their guard and both apply their
--      side effects -- a real GL ticket AND an inventory rollback for the
--      same batch. Fixed by moving the Status transition to be the FIRST
--      write inside each proc's transaction, guarded by
--      "AND Status = 'FOR POSTING'" with an immediate @@ROWCOUNT=1 check.
--      This uses ordinary SQL Server row locking as the serialization
--      point: whichever proc's UPDATE commits first holds an exclusive
--      lock on the ConversionBarcodeSummary row until it finishes, so the
--      other's matching UPDATE (once unblocked) finds 0 rows and aborts
--      BEFORE touching Inventory or GL -- not just a cosmetic check on an
--      already-corrupted state.
--
--  [3] Finalize's GL output-leg amount and Inventory.Cost update both
--      ignored the possibility that some of the converted output was
--      already sold between Submit and Finalize (Finalize can run an
--      arbitrary time later; output lots are sellable immediately at
--      Submit) -- the GL amount used the full original Qty, not whatever
--      Available actually remains, silently overstating the posted
--      Inventory value for a partially-sold lot with no reconciling entry.
--      This also contradicted this same module's OWN precedent:
--      spu_ReverseConversionBarcode already refuses to reverse when an
--      output lot's Available <> Quantity. Fixed by adding the identical
--      guard to Finalize: if any non-driploss output lot has been touched
--      (Available <> Quantity), Finalize is refused outright -- cost must
--      be finalized before any of the output is sold. A true-up/partial
--      GL entry was considered and rejected as unnecessary added
--      complexity; blocking matches the existing Reverse precedent exactly
--      and keeps the business rule simple: finalize first, then sell.
--
-- Also fixes the should-fix items from the same review:
--  [4] No existence/rowcount assertion on the VAT-split Inventory joins --
--      added, THROWs if a referenced Inventory row is missing (this
--      codebase does have a live hard-delete-by-SequenceNumber path
--      elsewhere, per ViewDeliveredShipDetailsDevEx.cs, so this isn't
--      purely defensive).
--  [5] FinalCost multiplication had no ISNULL guard -- wrapped with
--      ISNULL(o.FinalCost, o.UnitCost) as cheap insurance even though it's
--      currently unreachable (FinalCost is always seeded at Submit).
--  [6] A @FinalCosts row with a SeqNo that doesn't match any output line
--      was silently a no-op -- now asserted via rowcount check.
--  [9] Removed the redundant ROLLBACK before THROW 59305 (the CATCH block
--      already does this via XACT_STATE()).
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. JournalEntryMapping seed data for the new CONV-FINALIZE mnemonic.
-------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping WHERE Origin = 'IT' AND Mnemonic = 'CONV-FINALIZE')
BEGIN
    INSERT INTO dbo.JournalEntryMapping
        (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription,
         IsConditional, IsAmountFromSource, IsActive, Notes, AmountType, ConditionFlag, BranchCode)
    VALUES
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 1, 'D', '502',       'COS - VAT',                1, 1, 1, 'Source leg: consumed source lots, VAT-applicable',       'SOURCE_VAT',   NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 2, 'D', '501',       'COS - VAT EXEMPT',         1, 1, 1, 'Source leg: consumed source lots, VAT-exempt',           'SOURCE_VATEX', NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 3, 'C', '101040202', 'INVENTORY - VAT',           1, 1, 1, 'Source leg: consumed source lots, VAT-applicable',       'SOURCE_VAT',   NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 4, 'C', '101040201', 'INVENTORY - VAT EXEMPT',    1, 1, 1, 'Source leg: consumed source lots, VAT-exempt',           'SOURCE_VATEX', NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 5, 'D', '101040202', 'INVENTORY - VAT',           1, 1, 1, 'Output leg (reverse): created output lots, VAT-applicable', 'OUTPUT_VAT',   NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 6, 'D', '101040201', 'INVENTORY - VAT EXEMPT',    1, 1, 1, 'Output leg (reverse): created output lots, VAT-exempt',    'OUTPUT_VATEX', NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 7, 'C', '502',       'COS - VAT',                1, 1, 1, 'Output leg (reverse): created output lots, VAT-applicable', 'OUTPUT_VAT',   NULL, NULL),
        ('IT', 'CONV-FINALIZE', 'Conversion Finalize -- source consumption / output creation reclass', 8, 'C', '501',       'COS - VAT EXEMPT',         1, 1, 1, 'Output leg (reverse): created output lots, VAT-exempt',    'OUTPUT_VATEX', NULL, NULL);
END
GO

-------------------------------------------------------------------
-- 2. spu_ReverseConversionBarcode: close the TOCTOU race by moving the
--    Status transition to be the FIRST write inside the transaction.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_ReverseConversionBarcode_OLD_09022026150000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_ReverseConversionBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_ReverseConversionBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_ReverseConversionBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_ReverseConversionBarcode', 'spu_ReverseConversionBarcode_OLD_09022026150000';
END
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.spu_ReverseConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @ReversedBy      VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Fast-fail UX check (unlocked, just to avoid entering a
        -- transaction for an obviously-wrong request) -- NOT the
        -- authoritative guard; see the guarded UPDATE below for that.
        IF NOT EXISTS (SELECT 1 FROM dbo.ConversionBarcodeSummary WHERE ConversionRefNo = @ConversionRefNo AND Status = 'FOR POSTING')
            THROW 59211, 'This Conversion is not in FOR POSTING status (already finalized/posted, already reversed, or does not exist).', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.ConversionBarcodeOutputDetails AS o
            INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = o.NewInventorySeqNo
            WHERE o.ConversionRefNo = @ConversionRefNo
              AND i.Available <> i.Quantity
        )
            THROW 59212, 'Cannot reverse -- some converted stock has already been moved, sold, or transferred out.', 1;

        DECLARE @ExpectedSourceLines INT = (
            SELECT COUNT(*) FROM dbo.ConversionBarcodeSourceDetails WHERE ConversionRefNo = @ConversionRefNo);

        BEGIN TRANSACTION;

        -- Claim this conversion FIRST. This UPDATE's row lock is what
        -- actually serializes a concurrent Reverse-vs-Finalize race:
        -- whichever proc's guarded UPDATE commits first wins; the other's
        -- matching UPDATE (once unblocked by the lock) finds 0 rows and
        -- aborts here, before touching Inventory.
        UPDATE dbo.ConversionBarcodeSummary
        SET Status = 'REVERSED',
            ReversedBy = @ReversedBy,
            DateReversed = GETDATE()
        WHERE ConversionRefNo = @ConversionRefNo
          AND Status = 'FOR POSTING';

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK;
            THROW 59216, 'This Conversion is no longer in FOR POSTING status (concurrently finalized or reversed by another session).', 1;
        END

        UPDATE i
        SET i.Available = i.Available + s.Qty,
            i.IsStock = 1
        FROM dbo.Inventory AS i
        INNER JOIN dbo.ConversionBarcodeSourceDetails AS s
            ON s.InventorySeqNo = i.SequenceNumber
        WHERE s.ConversionRefNo = @ConversionRefNo;

        IF @@ROWCOUNT <> @ExpectedSourceLines
            THROW 59214, 'Cannot reverse -- one or more original source inventory lots no longer exist.', 1;

        UPDATE i
        SET i.Available = 0,
            i.IsStock = 0,
            i.LastMovementDate = GETDATE()
        FROM dbo.Inventory AS i
        INNER JOIN dbo.ConversionBarcodeOutputDetails AS o
            ON o.NewInventorySeqNo = i.SequenceNumber
        WHERE o.ConversionRefNo = @ConversionRefNo;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-------------------------------------------------------------------
-- 3. spu_FinalizeConversionBarcode: full rewrite addressing all findings.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode_OLD_09022026150000', 'P') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode', 'P') IS NOT NULL
        DROP PROCEDURE dbo.spu_FinalizeConversionBarcode;
END
ELSE IF OBJECT_ID('dbo.spu_FinalizeConversionBarcode', 'P') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.spu_FinalizeConversionBarcode', 'spu_FinalizeConversionBarcode_OLD_09022026150000';
END
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.spu_FinalizeConversionBarcode
    @ConversionRefNo VARCHAR(20),
    @FinalCosts      dbo.tt_ConversionFinalCostLines READONLY,
    @FinalizedBy     VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE @BranchCode VARCHAR(50), @Status VARCHAR(20);

        -- Fast-fail UX check (unlocked) -- NOT the authoritative guard;
        -- see the guarded UPDATE inside the transaction for that.
        SELECT @BranchCode = BranchCode, @Status = Status
        FROM dbo.ConversionBarcodeSummary
        WHERE ConversionRefNo = @ConversionRefNo;

        IF @BranchCode IS NULL
            THROW 59301, 'Conversion not found.', 1;

        IF @Status <> 'FOR POSTING'
            THROW 59302, 'This Conversion is not in FOR POSTING status (already finalized, reversed, or does not exist).', 1;

        -- Cannot finalize once any of the output has already been sold or
        -- moved -- same rule and same reasoning as
        -- spu_ReverseConversionBarcode's existing guard: cost must be
        -- settled before the stock moves, not retrofitted after.
        IF EXISTS (
            SELECT 1
            FROM dbo.ConversionBarcodeOutputDetails o
            INNER JOIN dbo.Inventory i ON i.SequenceNumber = o.NewInventorySeqNo
            WHERE o.ConversionRefNo = @ConversionRefNo
              AND o.IsDriploss = 0
              AND i.Available <> i.Quantity
        )
            THROW 59307, 'Cannot finalize -- some converted output has already been moved, sold, or transferred out. Final Cost must be set before any of the output is sold.', 1;

        IF EXISTS (
            SELECT 1 FROM @FinalCosts f
            INNER JOIN dbo.ConversionBarcodeOutputDetails o
                ON o.ConversionRefNo = @ConversionRefNo AND o.SeqNo = f.SeqNo
            WHERE o.IsDriploss = 1
        )
            THROW 59303, 'Cannot set a Final Cost override on a driploss line.', 1;

        IF EXISTS (SELECT 1 FROM @FinalCosts WHERE FinalCost < 0)
            THROW 59304, 'Final Cost cannot be negative.', 1;

        DECLARE @FinalCostRowCount INT = (SELECT COUNT(*) FROM @FinalCosts);

        BEGIN TRANSACTION;

        -- Claim this conversion FIRST -- see the matching comment in
        -- spu_ReverseConversionBarcode; this row lock is what actually
        -- closes the race, not the earlier unlocked @Status check above.
        UPDATE dbo.ConversionBarcodeSummary
        SET Status = 'POSTED',
            FinalizedBy = @FinalizedBy,
            DateFinalized = GETDATE()
        WHERE ConversionRefNo = @ConversionRefNo
          AND Status = 'FOR POSTING';

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK;
            THROW 59306, 'This Conversion is no longer in FOR POSTING status (concurrently finalized or reversed by another session).', 1;
        END

        -- Apply overrides (only for rows actually present in @FinalCosts --
        -- an unedited line keeps its existing FinalCost, seeded at Submit
        -- time to the system-computed UnitCost).
        UPDATE o
        SET o.FinalCost = f.FinalCost
        FROM dbo.ConversionBarcodeOutputDetails o
        INNER JOIN @FinalCosts f ON f.SeqNo = o.SeqNo
        WHERE o.ConversionRefNo = @ConversionRefNo;

        IF @@ROWCOUNT <> @FinalCostRowCount
        BEGIN
            ROLLBACK;
            THROW 59308, 'One or more Final Cost entries did not match an existing output line for this Conversion.', 1;
        END

        -- Push the (possibly overridden) final cost onto the actual
        -- Inventory lot. Safe to apply unconditionally now -- the
        -- Available <> Quantity guard above already confirmed nothing has
        -- been sold from any non-driploss output lot yet.
        UPDATE i
        SET i.Cost = ISNULL(o.FinalCost, o.UnitCost)
        FROM dbo.Inventory i
        INNER JOIN dbo.ConversionBarcodeOutputDetails o
            ON o.NewInventorySeqNo = i.SequenceNumber
        WHERE o.ConversionRefNo = @ConversionRefNo
          AND o.IsDriploss = 0;

        ------------------------------------------------------------------
        -- GL: source-consumption leg (Debit COGS / Credit Inventory,
        -- valued at ORIGINAL source cost -- unaffected by output FinalCost)
        -- and output-creation leg (the reverse, valued at FINAL cost).
        -- Both split VAT/VATEx by each lot's own Inventory.IsVat. Row-count
        -- asserted against each detail table so a since-deleted Inventory
        -- row (this codebase does have a hard-delete-by-SequenceNumber path
        -- elsewhere) can't silently drop value out of the GL computation.
        ------------------------------------------------------------------
        DECLARE
            @SourceVat    DECIMAL(18,2) = 0,
            @SourceVatEx  DECIMAL(18,2) = 0,
            @OutputVat    DECIMAL(18,2) = 0,
            @OutputVatEx  DECIMAL(18,2) = 0,
            @SourceLineCount INT = (SELECT COUNT(*) FROM dbo.ConversionBarcodeSourceDetails WHERE ConversionRefNo = @ConversionRefNo),
            @SourceJoinCount INT,
            @OutputLineCount INT = (SELECT COUNT(*) FROM dbo.ConversionBarcodeOutputDetails WHERE ConversionRefNo = @ConversionRefNo AND IsDriploss = 0),
            @OutputJoinCount INT;

        SELECT
            @SourceJoinCount = COUNT(*),
            @SourceVat   = ISNULL(SUM(CASE WHEN i.IsVat = 1 THEN s.Qty * s.Cost ELSE 0 END), 0),
            @SourceVatEx = ISNULL(SUM(CASE WHEN i.IsVat = 0 OR i.IsVat IS NULL THEN s.Qty * s.Cost ELSE 0 END), 0)
        FROM dbo.ConversionBarcodeSourceDetails s
        INNER JOIN dbo.Inventory i ON i.SequenceNumber = s.InventorySeqNo
        WHERE s.ConversionRefNo = @ConversionRefNo;

        IF @SourceJoinCount <> @SourceLineCount
        BEGIN
            ROLLBACK;
            THROW 59309, 'Cannot finalize -- one or more original source inventory lots no longer exist.', 1;
        END

        SELECT
            @OutputJoinCount = COUNT(*),
            @OutputVat   = ISNULL(SUM(CASE WHEN i.IsVat = 1 THEN o.Qty * ISNULL(o.FinalCost, o.UnitCost) ELSE 0 END), 0),
            @OutputVatEx = ISNULL(SUM(CASE WHEN i.IsVat = 0 OR i.IsVat IS NULL THEN o.Qty * ISNULL(o.FinalCost, o.UnitCost) ELSE 0 END), 0)
        FROM dbo.ConversionBarcodeOutputDetails o
        INNER JOIN dbo.Inventory i ON i.SequenceNumber = o.NewInventorySeqNo
        WHERE o.ConversionRefNo = @ConversionRefNo
          AND o.IsDriploss = 0;

        IF @OutputJoinCount <> @OutputLineCount
        BEGIN
            ROLLBACK;
            THROW 59310, 'Cannot finalize -- one or more output inventory lots no longer exist.', 1;
        END

        DECLARE @TicketNo BIGINT;
        EXEC GetTicketNumber @TicketNo OUTPUT;

        INSERT INTO TicketMaster
        (
            TicketDate, SupplementaryNumber, BranchCode, Origin,
            TicketNumber, ReferenceNumber, ReferenceKey,
            Owner, Particulars, EnteredBy,
            CheckedBy, ApprovedBy, Status, Mnemonic, Product
        )
        VALUES
        (
            GETDATE(), 0, @BranchCode, @BranchCode,
            @TicketNo, @ConversionRefNo, @ConversionRefNo,
            @FinalizedBy, 'CONVERSION FINALIZE ENTRY', @FinalizedBy,
            '*', '*', 'UPDATED', 'CONV-FINALIZE', NULL
        );

        -- GL account codes/legs resolved from JournalEntryMapping, not
        -- hardcoded -- matches this codebase's established convention.
        IF OBJECT_ID('tempdb..#Computed') IS NOT NULL
            DROP TABLE #Computed;

        SELECT
            M.Seq,
            M.DebitCredit,
            M.AccountCode,
            Amount =
                CASE M.AmountType
                    WHEN 'SOURCE_VAT'   THEN @SourceVat
                    WHEN 'SOURCE_VATEX' THEN @SourceVatEx
                    WHEN 'OUTPUT_VAT'   THEN @OutputVat
                    WHEN 'OUTPUT_VATEX' THEN @OutputVatEx
                    ELSE 0
                END
        INTO #Computed
        FROM dbo.JournalEntryMapping M
        WHERE M.Origin = 'IT' AND M.Mnemonic = 'CONV-FINALIZE' AND M.IsActive = 1;

        IF NOT EXISTS (SELECT 1 FROM #Computed)
        BEGIN
            ROLLBACK;
            THROW 59311, 'No active JournalEntryMapping found for CONV-FINALIZE. Verify seed data.', 1;
        END

        INSERT INTO TicketDetails
        (
            TicketDate, SupplementaryNumber, BranchCode, ReferenceKey,
            TicketNumber, ReferenceNumber,
            AccountCode, Debit, Credit, CostCenter
        )
        SELECT
            GETDATE(), 0, @BranchCode, @ConversionRefNo,
            @TicketNo, @ConversionRefNo,
            AccountCode,
            CASE WHEN DebitCredit = 'D' THEN Amount ELSE 0 END,
            CASE WHEN DebitCredit = 'C' THEN Amount ELSE 0 END,
            ' '
        FROM #Computed
        WHERE Amount <> 0
        ORDER BY Seq;

        DECLARE @TotalDebit DECIMAL(18,2), @TotalCredit DECIMAL(18,2);
        SELECT @TotalDebit = ISNULL(SUM(Debit), 0), @TotalCredit = ISNULL(SUM(Credit), 0)
        FROM TicketDetails WHERE TicketNumber = @TicketNo AND ReferenceKey = @ConversionRefNo;

        IF @TotalDebit <> @TotalCredit
        BEGIN
            THROW 59305, 'Finalize GL entry did not balance -- Debit and Credit totals differ.', 1;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: JournalEntryMapping (+CONV-FINALIZE mnemonic, 8 rows), spu_ReverseConversionBarcode (race-safe status guard), spu_FinalizeConversionBarcode (race-safe status guard, partial-sale block, mapping-driven GL accounts, row-count assertions).';
