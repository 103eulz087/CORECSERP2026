
CREATE PROCEDURE [dbo].[sp_SalesQtyToInventoryQtyEODSalesInvDeduct] 
    @parmSeqNo BIGINT,
    @parmBranch CHAR(3),
    @parmProduct CHAR(5),
    @parmRunningQtySold DECIMAL(18,3),
    @parmsellingprice DECIMAL(18,2),   
    @TotalCost DECIMAL(18,3) OUTPUT -- UPGRADED TO 18,3 for precise math
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- =========================================================================
    -- THE SAFEPOINT: modular transaction handling
    -- =========================================================================
    DECLARE @TranCounter INT = @@TRANCOUNT;
    IF @TranCounter > 0
        SAVE TRANSACTION EODDeductSave;
    ELSE
        BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @iSeqNo BIGINT, @iAvailable DECIMAL(18,3), @iCost DECIMAL(18,3); -- UPGRADED @iCost
        DECLARE @ProductDescription VARCHAR(250);
        DECLARE @QtyToDeduct DECIMAL(18,3);
        DECLARE @RunningQtySold DECIMAL(18,3) = @parmRunningQtySold;
        
        SET @TotalCost = ISNULL(@TotalCost, 0);

        WHILE (@RunningQtySold > 0)
        BEGIN
            SET @iSeqNo = NULL;
            SET @iAvailable = 0;

            -- =========================================================================
            -- STEP 1: LOCK AND LOAD (Added READPAST to prevent EOD freezes)
            -- =========================================================================
            SELECT TOP(1) 
                @iSeqNo = SequenceNumber,
                @iAvailable = Available, 
                @iCost = ISNULL(Cost, 0),
                @ProductDescription = Description
            FROM Inventory WITH (UPDLOCK, ROWLOCK, READPAST) 
            WHERE Branch = @parmBranch 
              AND Product = @parmProduct 
              AND Available > 0
            ORDER BY SequenceNumber ASC;

            -- BREAK if no inventory is left
            IF (@iSeqNo IS NULL) BREAK; 

            -- =========================================================================
            -- STEP 2: FOOLPROOF MATH
            -- =========================================================================
            SET @QtyToDeduct = IIF(@RunningQtySold >= @iAvailable, @iAvailable, @RunningQtySold);

            -- =========================================================================
            -- STEP 3: EXPLICIT UPDATE
            -- =========================================================================
            UPDATE Inventory 
            SET Available = (Available - @QtyToDeduct)
            WHERE SequenceNumber = @iSeqNo;

            -- =========================================================================
            -- STEP 4: WRITE TO LEDGERS
            -- =========================================================================
            INSERT INTO InventoryLedgerDeduct(
                SalesID, InventorySequenceNumber, Branch, Product, Description, BegQty, 
                Quantity, Cost, TotalCost, SellingPrice, TotalSales, GrossProfit, 
                isReturned, DateDeducted
            )
            VALUES(
                @parmSeqNo, @iSeqNo, @parmBranch, @parmProduct, @ProductDescription, @iAvailable, 
                @QtyToDeduct, @iCost, (@QtyToDeduct * @iCost), @parmsellingprice, (@QtyToDeduct * @parmsellingprice), 
                ((@QtyToDeduct * @parmsellingprice) - (@QtyToDeduct * @iCost)), 0, GETDATE()
            );
            
            INSERT INTO InventoryLedger (
                SequenceRefNum, OriginBranch, DestinationBranch, DateProcessed, Product, 
                Description, BegQty, QtyIN, QtyOut, EndQty, Cost, Remarks, ProcessedBy
            )
            VALUES(
                @iSeqNo, @parmBranch, @parmBranch, GETDATE(), @parmProduct, 
                @ProductDescription, @iAvailable, 0, @QtyToDeduct, (@iAvailable - @QtyToDeduct), 
                @iCost, 'BATCH DEDUCT FROM POS', 'System'
            );

            -- Prepare for next loop iteration
            SET @RunningQtySold = @RunningQtySold - @QtyToDeduct;
            SET @TotalCost = @iCost--@TotalCost + (@iCost * @QtyToDeduct);
        END;

        -- ====================================================================
        -- NEW LOGIC: THE SILENT SHORTAGE LOG
        -- ====================================================================
        IF (@RunningQtySold > 0)
        BEGIN
            -- RTRIM removes trailing spaces from the char(5) product code for cleaner logs
            DECLARE @ShortageLog NVARCHAR(500) = 'Shortage Warning: POS sold ' + CAST(@parmRunningQtySold AS VARCHAR(20)) + 
                                                 ' of ' + RTRIM(@parmProduct) + ', but inventory fell short by ' + CAST(@RunningQtySold AS VARCHAR(20)) + ' units.';
            
            INSERT INTO HistoryLogs (UserID, DateExecute, ActionLogs, BranchCode) 
            VALUES ('System', GETDATE(), @ShortageLog, @parmBranch);
        END

        -- Safely commit
        IF @TranCounter = 0
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        -- Safely rollback without destroying the massive EOD parent loop!
        IF @TranCounter = 0
            ROLLBACK TRANSACTION;
        ELSE
            IF XACT_STATE() <> -1
                ROLLBACK TRANSACTION EODDeductSave;

        -- Bubble the error up so the parent script knows a specific row failed
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR (@ErrorMessage, 16, 1);
    END CATCH
END;