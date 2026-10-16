
CREATE   PROCEDURE [dbo].[sp_SubmitConversionRaw_JFC]
(
      @BranchCode          varchar(5)
    , @ConID               int
    , @ConversionType      varchar(20)  -- 'OneToMany' or 'ManyToOne'
    , @ConvertedBy         varchar(100)
    , @DateConverted       datetime = NULL
    , @IsErrorCorrect      bit = 0
    , @IsConfirm           bit = 0
    , @CuttingFee          money

    -- OneToMany inputs
    , @SourceProductCode   varchar(10) = NULL
    , @SourceDescription   varchar(200) = NULL
    , @SourceSequenceNumber int = NULL
    , @SourceQty           decimal(18,3) = NULL

    -- ManyToOne inputs
    , @DestProductCode     varchar(10) = NULL
    , @DestDescription     varchar(200) = NULL
    , @ActualQtyOut        decimal(18,3) = NULL

    -- TVPs (only one will be used depending on type)
    , @OneToManyLines      dbo.TVP_Conversion_OneToManyLines_JFC READONLY
    , @ManyToOneLines      dbo.TVP_Conversion_ManyToOneLines READONLY
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @DateConverted IS NULL
        SET @DateConverted = GETDATE();

    BEGIN TRY
        BEGIN TRAN;

        /*============================
          VALIDATION
        ============================*/
        IF @BranchCode IS NULL OR LTRIM(RTRIM(@BranchCode)) = ''
            THROW 51001, 'BranchCode is required.', 1;

        IF @ConID IS NULL
            THROW 51002, 'ConID is required.', 1;

        IF @ConversionType NOT IN ('OneToMany','ManyToOne')
            THROW 51003, 'ConversionType must be OneToMany or ManyToOne.', 1;

        IF @ConversionType = 'OneToMany'
        BEGIN
            IF @SourceProductCode IS NULL OR LTRIM(RTRIM(@SourceProductCode)) = ''
                THROW 51004, 'SourceProductCode is required for OneToMany.', 1;

            IF @SourceQty IS NULL OR @SourceQty <= 0
                THROW 51005, 'SourceQty must be > 0 for OneToMany.', 1;

            IF NOT EXISTS (SELECT 1 FROM @OneToManyLines)
                THROW 51006, 'OneToManyLines is empty.', 1;

            IF EXISTS (SELECT 1 FROM @OneToManyLines WHERE ActualQty <= 0)
                THROW 51007, 'All OneToMany lines must have ActualQty > 0.', 1;

            -- Optional safety: total output cannot exceed source qty
            IF (SELECT SUM(ActualQty) FROM @OneToManyLines) > @SourceQty
                THROW 51008, 'Total ActualQty cannot exceed SourceQty (OneToMany).', 1;
        END

        IF @ConversionType = 'ManyToOne'
        BEGIN
            IF @DestProductCode IS NULL OR LTRIM(RTRIM(@DestProductCode)) = ''
                THROW 51009, 'DestProductCode is required for ManyToOne.', 1;

            IF @ActualQtyOut IS NULL OR @ActualQtyOut <= 0
                THROW 51010, 'ActualQtyOut must be > 0 for ManyToOne.', 1;

            IF NOT EXISTS (SELECT 1 FROM @ManyToOneLines)
                THROW 51011, 'ManyToOneLines is empty.', 1;

            IF EXISTS (SELECT 1 FROM @ManyToOneLines WHERE QtyUsed <= 0)
                THROW 51012, 'All ManyToOne lines must have QtyUsed > 0.', 1;
        END

        /*============================
          CLEAR EXISTING STAGING (avoid duplicates)
        ============================*/
        DELETE FROM dbo.TempConversionDetails WHERE ConID = @ConID;
        DELETE FROM dbo.TempConversionSummary WHERE ConID = @ConID;

        /*============================
          INSERT DETAILS (computed fields)
        ============================*/
        IF @ConversionType = 'OneToMany'
        BEGIN
            DECLARE @TotalActualQty decimal(18,3);
            SELECT @TotalActualQty = SUM(ActualQty) FROM @OneToManyLines;

            INSERT INTO dbo.TempConversionDetails
            (
                BranchCode, ConID, SequenceRefNum,
                SourceProductCode, SourceDescription, SourceQty, SourceCost, SourceTotalCost,
                Product, Description, Quantity, ActualQty,
                Cost, PercentagePerPart, FinalRatio, TotalCost, SourceAmountPerPart, Barcode
            )
            SELECT
                @BranchCode,
                @ConID,
                1 AS SequenceRefNum,
                @SourceProductCode,
                COALESCE(@SourceDescription,''),
                @SourceQty,
                0 AS SourceCost,
                0 AS SourceTotalCost,

                l.ProductCode,
                l.Description,
                l.ActualQty AS Quantity,
                l.ActualQty AS ActualQty,

                0 AS Cost,
                CAST(l.ActualQty / NULLIF(@SourceQty,0) AS float) AS PercentagePerPart,
                CAST(l.ActualQty / NULLIF(@SourceQty,0) AS float) AS FinalRatio,
                0 AS TotalCost,
                0 AS SourceAmountPerPart,
                l.Barcode
            FROM @OneToManyLines l;
        END
        ELSE
        BEGIN
            -- ManyToOne
            DECLARE @TotalInputQty decimal(18,3);
            SELECT @TotalInputQty = SUM(QtyUsed) FROM @ManyToOneLines;

            INSERT INTO dbo.TempConversionDetails
            (
                BranchCode, ConID, SequenceRefNum,
                SourceProductCode, SourceDescription, SourceQty, SourceCost, SourceTotalCost,
                Product, Description, Quantity, ActualQty,
                Cost, PercentagePerPart, FinalRatio, TotalCost, SourceAmountPerPart, Barcode
            )
            SELECT
                @BranchCode,
                @ConID,
                1 AS SequenceRefNum,

                l.SourceProductCode,
                l.SourceDescription,

                -- ✅ IMPORTANT RECOMMENDATION:
                -- For ManyToOne, store SourceQty as QtyUsed (what you actually consume),
                -- not the "available" qty from the UI.
                l.QtyUsed AS SourceQty,

                0 AS SourceCost,
                0 AS SourceTotalCost,

                @DestProductCode AS Product,
                COALESCE(@DestDescription,'') AS Description,

                l.QtyUsed AS Quantity,
                @ActualQtyOut AS ActualQty,

                0 AS Cost,
                CAST(l.QtyUsed / NULLIF(@TotalInputQty,0) AS float) AS PercentagePerPart,
                CAST(@ActualQtyOut / NULLIF(@TotalInputQty,0) AS float) AS FinalRatio,
                0 AS TotalCost,
                0 AS SourceAmountPerPart,
                l.Barcode
            FROM @ManyToOneLines l;
        END

        /*============================
          INSERT SUMMARY (computed)
        ============================*/
        IF @ConversionType = 'OneToMany'
        BEGIN
            DECLARE @TotActual decimal(18,3);
            SELECT @TotActual = SUM(ActualQty) FROM @OneToManyLines;

            INSERT INTO dbo.TempConversionSummary
            (
                BranchCode, ConID, SourceSequenceNumber, SourceQty, SourceCost,
                SourceTotalAmount, TotalItemsConverted, TotalQtyConverted, ActualQty,
                ConversionType, DateConverted, ConvertedBy, isErrorCorrect, isConfirm
            )
            VALUES
            (
                @BranchCode, @ConID, @SourceSequenceNumber, @SourceQty, 0,
                0, (SELECT COUNT(*) FROM @OneToManyLines), @TotActual, @TotActual,
                @ConversionType, @DateConverted, @ConvertedBy, @IsErrorCorrect, @IsConfirm
            );
        END
        ELSE
        BEGIN
            DECLARE @TotInput decimal(18,3);
            SELECT @TotInput = SUM(QtyUsed) FROM @ManyToOneLines;

            INSERT INTO dbo.TempConversionSummary
            (
                BranchCode, ConID, SourceSequenceNumber, SourceQty, SourceCost,
                SourceTotalAmount, TotalItemsConverted, TotalQtyConverted, ActualQty,
                ConversionType, DateConverted, ConvertedBy, isErrorCorrect, isConfirm
            )
            VALUES
            (
                @BranchCode, @ConID, NULL, @TotInput, 0,
                0, (SELECT COUNT(*) FROM @ManyToOneLines), @TotInput, @ActualQtyOut,
                @ConversionType, @DateConverted, @ConvertedBy, @IsErrorCorrect, @IsConfirm
            );
        END

        /*============================
          PROCESS (your existing procedure)
        ============================*/

        IF EXISTS(SELECT TOP(1) 1 FROM CompanyProfile WHERE CompanyName='JFC')
        BEGIN
             EXEC dbo.sp_ConversionProcess_JFC
             @parmconid      = @ConID,
             @parmbranchcode = @BranchCode,
             @parmcuttingfee = @CuttingFee
        END
        ELSE
        BEGIN
              EXEC dbo.sp_ConversionProcess
             @parmconid      = @ConID,
             @parmbranchcode = @BranchCode;
        END

      

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
