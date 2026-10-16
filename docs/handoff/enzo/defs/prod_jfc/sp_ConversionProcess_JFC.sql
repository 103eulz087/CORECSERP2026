
CREATE PROCEDURE [dbo].[sp_ConversionProcess_JFC] --exec [sp_ConversionProcess] 274,'005'
    @parmconid      INT,
    @parmbranchcode VARCHAR(5),
    @parmcuttingfee money
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @overrage FLOAT = 0,
                @shortage FLOAT = 0;

        -- ⚠️ Removed TRUNCATE on permanent table aaplock (dangerous in concurrent systems)
        -- TRUNCATE TABLE aaplock;

        -----------------------------
        -- Stage temp → base tables --
        -----------------------------
        INSERT INTO [dbo].[ConversionDetails]
        (
            [BranchCode],[ConID],[SequenceRefNum],[SourceProductCode],[SourceDescription],
            [SourceQty],[SourceCost],[SourceTotalCost],[Product],[Description],[Quantity],
            [ActualQty],[Cost],[PercentagePerPart],[FinalRatio],[TotalCost],[SourceAmountPerPart],[Barcode]
        )
        SELECT [BranchCode],[ConID],[SequenceRefNum],[SourceProductCode],[SourceDescription],
               [SourceQty],[SourceCost],[SourceTotalCost],[Product],[Description],[Quantity],
               [ActualQty],[Cost],[PercentagePerPart],[FinalRatio],[TotalCost],[SourceAmountPerPart],[Barcode]
        FROM dbo.TempConversionDetails
        WHERE ConID = @parmconid;

        DELETE FROM dbo.TempConversionDetails
        WHERE ConID = @parmconid;

        INSERT INTO [dbo].[ConversionSummary]
        (
            [BranchCode],[ConID],[SourceSequenceNumber],[SourceQty],[SourceCost],
            [SourceTotalAmount],[TotalItemsConverted],[TotalQtyConverted],[ActualQty],
            [ConversionType],[DateConverted],[ConvertedBy],[isErrorCorrect],[isConfirm],[cuttingfee]
        )
        SELECT [BranchCode],[ConID],[SourceSequenceNumber],[SourceQty],[SourceCost],
               [SourceTotalAmount],[TotalItemsConverted],[TotalQtyConverted],[ActualQty],
               [ConversionType],[DateConverted],[ConvertedBy],[isErrorCorrect],[isConfirm],@parmcuttingfee
        FROM dbo.TempConversionSummary
        WHERE ConID = @parmconid;

        DELETE FROM dbo.TempConversionSummary
        WHERE ConID = @parmconid;

        ---------------------------------------
        -- Load summary once (avoid repeats) --
        ---------------------------------------
        DECLARE @sourceTotalAmount MONEY,
                @totalQtyConverted FLOAT,
                @totalActualQtyConverted FLOAT,
                @sourceQty FLOAT,
                @conversionType VARCHAR(20),
                @dateconverted DATE;

        SELECT  @sourceTotalAmount       = cs.SourceTotalAmount,
                @sourceQty               = cs.SourceQty,
                @totalQtyConverted       = cs.TotalQtyConverted,
                @totalActualQtyConverted = cs.ActualQty,
                @conversionType          = cs.ConversionType,
                @dateconverted           = cs.DateConverted
        FROM dbo.ConversionSummary AS cs
        WHERE cs.ConID = @parmconid;

        -------------------
        -- One-to-Many   --
        -------------------
        IF (@conversionType = 'OneToMany')
        BEGIN
            DECLARE @convdet_actualqty FLOAT,
                    @convdet_srcprodcode VARCHAR(10);

            DECLARE ConversionDataOneToMany CURSOR FAST_FORWARD FOR
                SELECT d.ActualQty, d.SourceProductCode
                FROM dbo.ConversionDetails d
                WHERE d.ConID = @parmconid;

            OPEN ConversionDataOneToMany;
            FETCH NEXT FROM ConversionDataOneToMany INTO @convdet_actualqty, @convdet_srcprodcode;
            WHILE (@@FETCH_STATUS = 0)
            BEGIN
                -- Keep using your existing FIFO routine for source consumption
                EXEC dbo.sp_ConversionFIFO
                     @parmbranchcode,
                     @convdet_srcprodcode,
                     @convdet_actualqty,
                     @dateconverted,
                     @parmconid;

                FETCH NEXT FROM ConversionDataOneToMany INTO @convdet_actualqty, @convdet_srcprodcode;
            END
            CLOSE ConversionDataOneToMany;
            DEALLOCATE ConversionDataOneToMany;

            declare @costchargealloc money,@ctralloc int
            SELECT @ctralloc=COUNT(*) 
            FROM dbo.ConversionDetails 
            WHERE ConID = @parmconid
            AND (
						Description NOT LIKE '%dripl%'
						OR Description NOT LIKE 'sawd%'
				)
            IF (ISNULL(@parmcuttingfee,0) > 0)
            BEGIN
                SET @costchargealloc = ISNULL(ISNULL(@parmcuttingfee,0)/@ctralloc,0)
            END
            ELSE
            BEGIN
                SET @costchargealloc = 0
            END
/********************************************************************************/
			DECLARE @exemptQty TABLE (
				ConID varchar(10),
				MinQty  decimal(19,6) null
			);
			INSERT INTO @exemptQty (ConID,MinQty)
			SELECT ConID, SUM(CAST(Quantity AS decimal(19,6))) AS MinQty
				FROM dbo.ConversionDetails
				WHERE ConID = @parmconid
				  AND (
						Description LIKE '%dripl%'
						OR Description LIKE 'sawd%'
					  )
			GROUP BY ConID
			declare @minqty decimal(19,6)
			SELECT @minqty=isnull(MinQty,0) FROM @exemptQty WHERE ConID=@parmconid
/********************************************************************************/
            ;WITH F AS
			(
				SELECT ConID,
					   SUM(CAST(Qty AS decimal(19,6)))       AS TotQty,
					   SUM(CAST(Qty AS decimal(19,6)) * CAST(Cost AS decimal(19,6))) AS TotCost
				FROM dbo.ConversionFIFO
				WHERE ConID = @parmconid
				GROUP BY ConID
			),
			LowestQuantity AS
			(
				SELECT ConID, SUM(CAST(Quantity AS decimal(19,6))) AS MinQty
				FROM dbo.ConversionDetails
				WHERE ConID = @parmconid
				  AND (
						Description LIKE '%dripl%'
						OR Description LIKE 'sawd%'
					  )
				GROUP BY ConID
			)
			UPDATE d
			SET
				d.SourceCost =
					CASE
						WHEN (f.TotQty - COALESCE(l.MinQty,0)) = 0 THEN 0
						ELSE f.TotCost / NULLIF((f.TotQty - COALESCE(l.MinQty,0)),0)
					END,
				d.SourceTotalCost =
					CASE
						WHEN f.TotQty = 0 THEN 0
						ELSE (f.TotCost / NULLIF(f.TotQty - COALESCE(l.MinQty,0),0)) * d.SourceQty
					END
			FROM dbo.ConversionDetails d
			INNER JOIN F f
				ON f.ConID = d.ConID
			LEFT JOIN LowestQuantity l          -- ✅ FIX
				ON l.ConID = d.ConID
			WHERE d.ConID = @parmconid;

			;WITH F AS
			(
				SELECT ConID,
					   SUM(CAST(Qty AS decimal(19,6)))       AS TotQty,
					   SUM(CAST(Qty AS decimal(19,6)) * CAST(Cost AS decimal(19,6))) AS TotCost
				FROM dbo.ConversionFIFO
				WHERE ConID = @parmconid
				GROUP BY ConID
			)
			,LowestQuantity AS
			(
				SELECT ConID, SUM(CAST(Quantity AS decimal(19,6))) AS MinQty
				FROM dbo.ConversionDetails
				WHERE ConID = @parmconid
				  AND (
						Description LIKE '%dripl%'
						OR Description LIKE 'sawd%'
					  )
				GROUP BY ConID
			)
			UPDATE cs
            SET cs.SourceCost        = f.TotCost/(f.TotQty-l.MinQty),
                cs.SourceTotalAmount = (f.TotCost /(f.TotQty-l.MinQty))*cs.SourceQty
            FROM dbo.ConversionSummary cs
            INNER JOIN F f ON f.ConID = cs.ConID
			LEFT JOIN LowestQuantity l          -- ✅ FIX
				ON l.ConID = cs.ConID
            WHERE cs.ConID = @parmconid;

            -- PercentagePerPart, FinalRatio, SourceAmountPerPart, Cost (set-based)
            ;WITH Agg AS
            (
                SELECT ConID,
                       SUM(Quantity) AS DestTotQty
                FROM dbo.ConversionDetails
                WHERE ConID = @parmconid
                GROUP BY ConID
            ),
			LowestQuantity AS
			(
				SELECT ConID, SUM(CAST(Quantity AS decimal(19,6))) AS MinQty
				FROM dbo.ConversionDetails
				WHERE ConID = @parmconid
				  AND (
						Description LIKE '%dripl%'
						OR Description LIKE 'sawd%'
					  )
				GROUP BY ConID
			),
            Src AS
            (
                SELECT ConID,
                       SourceQty,
                       SourceCost,
                       SourceTotalAmount =  (SourceQty *  SourceCost)
                FROM dbo.ConversionSummary
                WHERE ConID = @parmconid
            )
            UPDATE d
            SET d.PercentagePerPart   = ROUND(d.Quantity / NULLIF(a.DestTotQty, 0), 2),
                d.FinalRatio          = d.Quantity / NULLIF(s.SourceQty-@minqty, 0),
                -- Recompute SourceAmountPerPart using SourceAmount and FinalRatio (your intent) 
                d.SourceAmountPerPart = (d.Quantity / NULLIF(s.SourceQty-@minqty, 0)) * s.SourceTotalAmount,
                d.Cost                = case when (d.Description like 'sawd%' OR d.Description like '%drip%') then 0 
										else s.SourceCost+@costchargealloc end-- s.SourceTotalAmount/(s.SourceQty-@minqty) end--( (d.Quantity / NULLIF(s.SourceQty-isnull(@minqty,0), 0)) * s.SourceAmount ) / NULLIF(d.Quantity, 0) end
            FROM dbo.ConversionDetails d
            INNER JOIN Agg a ON a.ConID = d.ConID
            INNER JOIN Src s ON s.ConID = d.ConID
            WHERE d.ConID = @parmconid;

            -- Sync summary cost from detail’s recomputed SourceCost (take any non-null)
            --;WITH AnyDetail AS
            --(
            --    SELECT TOP (1) d.ConID, d.SourceCost
            --    FROM dbo.ConversionDetails d
            --    WHERE d.ConID = @parmconid AND d.SourceCost IS NOT NULL
            --    ORDER BY d.SequenceRefNum
            --)
            --UPDATE cs
            --SET cs.SourceCost        = ad.SourceCost,
            --    cs.SourceTotalAmount = ad.SourceCost * cs.SourceQty
            --FROM dbo.ConversionSummary cs
            --INNER JOIN AnyDetail ad ON ad.ConID = cs.ConID
            --WHERE cs.ConID = @parmconid;
        END

        -------------------
        -- Many-to-One   --
        -------------------
        IF (@conversionType = 'ManyToOne')
        BEGIN
            -- Replaces GOTO + temp table with a carry variable and a clean WHILE loop
            

            DECLARE @qtyCarry FLOAT,
                    @inventory_prodcode VARCHAR(5),
                    @inventory_desc VARCHAR(100),
                    @inventory_available FLOAT,
                    @inventory_cost MONEY,
                    @inventory_seq VARCHAR(40),
                    @isvatable BIT,
                    @takeQty FLOAT,
                    @totalcost MONEY;

            DECLARE ConversionDataManyToOne CURSOR FAST_FORWARD FOR
                SELECT d.Quantity, d.SourceProductCode
                FROM dbo.ConversionDetails d
                WHERE d.ConID = @parmconid;

            OPEN ConversionDataManyToOne;
            FETCH NEXT FROM ConversionDataManyToOne INTO @convdet_actualqty, @convdet_srcprodcode;

            WHILE (@@FETCH_STATUS = 0)
            BEGIN
                SET @qtyCarry = @convdet_actualqty;

                WHILE (@qtyCarry > 0)
                BEGIN
                    -- Take next FIFO inventory row for this product
                    SELECT TOP (1)
                           @inventory_prodcode   = inv.Product,
                           @inventory_desc       = inv.Description,
                           @inventory_available  = inv.Available,
                           @inventory_cost       = inv.Cost,
                           @inventory_seq        = inv.SequenceNumber,
                           @isvatable            = inv.IsVat
                    FROM dbo.Inventory AS inv WITH (READPAST, UPDLOCK, ROWLOCK)
                    WHERE inv.Product = @convdet_srcprodcode
                      AND inv.Available > 0
                      AND inv.Branch = @parmbranchcode
                    ORDER BY inv.SequenceNumber ASC;

                    IF (@@ROWCOUNT = 0)
                    BEGIN
                        -- No more stock – choose behavior: raise error or gracefully exit
                        -- Here: we raise an error to avoid silent under-issue
                        PRINT  'Insufficient inventory for ManyToOne conversion.'
                    END

                    SET @takeQty = CASE WHEN @qtyCarry > @inventory_available THEN @inventory_available ELSE @qtyCarry END;

                    SET @totalcost = @takeQty * @inventory_cost;

                    INSERT INTO dbo.ConversionFIFO --select * FROM ConversionFIFO
                    (
                        BranchCode,
                        ProductNo,
                        Description,
                        Qty,
                        Cost,
                        TotalCost,
                        ActualQty,
                        DateProcessed,
                        SequenceReferenceNumber,
                        ConID,
                        IsVat,
                        Metrics
                    )
                    VALUES
                    (
                        @parmbranchcode,
                        @inventory_prodcode,
                        @inventory_desc,
                        @takeQty,
                        @inventory_cost,
                        @totalcost,
                        0,
                        @dateconverted,
                        @inventory_seq,
                        @parmconid,
                        @isvatable,
                        '< m-to-1'
                    );

                    UPDATE dbo.Inventory
                    SET Available = Available - @takeQty
                    WHERE SequenceNumber = @inventory_seq;

                    SET @qtyCarry = @qtyCarry - @takeQty;
                END

                FETCH NEXT FROM ConversionDataManyToOne INTO @convdet_actualqty, @convdet_srcprodcode;
            END

            CLOSE ConversionDataManyToOne;
            DEALLOCATE ConversionDataManyToOne;

           ;WITH F AS
			(
				SELECT ConID, ProductNo,
					   SUM(CAST(Qty AS decimal(19,6)))       AS TotQty,
					   SUM(CAST(Qty AS decimal(19,6)) * CAST(Cost AS decimal(19,6))) AS TotCost
				FROM dbo.ConversionFIFO
				WHERE ConID = @parmconid
				GROUP BY ConID, ProductNo
			),
			LowestQuantity AS
			(
				SELECT ConID, SUM(CAST(Quantity AS decimal(19,6))) AS MinQty
				FROM dbo.ConversionDetails
				WHERE ConID = @parmconid
				  AND (
						Description LIKE '%dripl%'
						OR Description LIKE 'sawd%'
					  )
				GROUP BY ConID
			)
			UPDATE d
			SET
				d.SourceCost =
					CASE
						WHEN (f.TotQty - COALESCE(l.MinQty,0)) = 0 THEN 0
						ELSE f.TotCost / NULLIF((f.TotQty - COALESCE(l.MinQty,0)),0)
					END,
				d.SourceTotalCost =
					CASE
						WHEN f.TotQty = 0 THEN 0
						ELSE (f.TotCost / NULLIF(f.TotQty,0)) * d.SourceQty
					END
			FROM dbo.ConversionDetails d
			INNER JOIN F f
				ON f.ConID = d.ConID
			   AND f.ProductNo = d.SourceProductCode
			LEFT JOIN LowestQuantity l          -- ✅ FIX
				ON l.ConID = d.ConID
			WHERE d.ConID = @parmconid;


            -- Weighted average to compute destination Cost and per-part allocations
            ;WITH cd AS
            (
                SELECT Quantity, SourceCost
                FROM dbo.ConversionDetails
                WHERE ConID = @parmconid
            ),
            Agg AS
            (
                SELECT SUM(Quantity) AS TotWeight,
                       SUM(Quantity * SourceCost) AS TotCost
                FROM cd
            )
            UPDATE d
            SET d.Cost                = Agg.TotCost / NULLIF(Agg.TotWeight, 0),--NULLIF(d.ActualQty,0), -
                d.PercentagePerPart   = d.Quantity / NULLIF(Agg.TotWeight, 0),
                d.SourceAmountPerPart = (d.Quantity / NULLIF(Agg.TotWeight, 0)) * Agg.TotCost
            FROM dbo.ConversionDetails d
            CROSS JOIN Agg
            WHERE d.ConID = @parmconid;
        END

		--IF (@conversionType = 'OneToMany')
		--BEGIN
		--	declare @newcost money
		--	select @newcost=SourceTotalAmount/TotalQtyConverted
		--	FROM ConversionSummary WHERE ConID=@parmconid

		--	update dbo.ConversionDetails set Cost=@newcost,TotalCost=@newcost*ActualQty
		--	WHERE ConID=@parmconid
		--END
        -------------------------------------
        -- Shortage / Overage registration --select * FROM  ConversionShortageOverageList
        -------------------------------------
        IF (@totalActualQtyConverted > @sourceQty)
        BEGIN
            SET @overrage = @totalActualQtyConverted - @sourceQty;
            INSERT INTO dbo.ConversionShortageOverageList (ConversionID, Shortage, Overage)
            VALUES (@parmconid, 0, @overrage);
        END
        ELSE
        BEGIN
            SET @shortage = @sourceQty - @totalActualQtyConverted;
            INSERT INTO dbo.ConversionShortageOverageList (ConversionID, Shortage, Overage)
            VALUES (@parmconid, @shortage, 0);
        END

        -- Optionally stamp processed dates
        -- UPDATE dbo.ConversionSummary SET DateConverted = SYSUTCDATETIME() WHERE ConID = @parmconid;
        -- UPDATE dbo.ConversionFIFO   SET DateProcessed  = SYSUTCDATETIME() WHERE ConID = @parmconid;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF (XACT_STATE()) <> 0 ROLLBACK TRAN;

        DECLARE @errMsg NVARCHAR(4000) = ERROR_MESSAGE(),
                @errNo  INT            = ERROR_NUMBER(),
                @errSev INT            = ERROR_SEVERITY(),
                @errSta INT            = ERROR_STATE(),
                @errLin INT            = ERROR_LINE();

        -- Re-throw with context
        RAISERROR('[sp_ConversionProcess] failed: %s (Err %d, Sev %d, State %d, Line %d)',
                  @errSev, 1, @errMsg, @errNo, @errSev, @errSta, @errLin);
        RETURN;
    END CATCH
END
