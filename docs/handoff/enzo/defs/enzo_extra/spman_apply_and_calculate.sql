
CREATE PROC [dbo].[spman_apply_and_calculate]
    @brcode char(3),
    @petsa date,
    @machinename varchar(20),
    @Items dbo.ManipItemType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ToDate date = DATEADD(day, 1, @petsa);

    
	BEGIN TRY
        BEGIN TRAN;

    WITH cte AS (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY ReferenceNo
                   ORDER BY ReferenceNo DESC
               ) AS rn
        FROM BatchSalesSummary
        WHERE BranchCode=@brcode 
        AND MachineUsed=@machinename 
        AND Transdate >= @petsa and Transdate < @ToDate
    )
    DELETE FROM cte WHERE rn > 1;
    ----------------------------------------------------------------------
    -- (A) Audit trail (recommended): store only changed rows from @Items
    --     This replaces the app inserting into ManipOR row-by-row. [1](https://onedrive.live.com?cid=C2F0E9F54FBC8D29&id=C2F0E9F54FBC8D29!129893)
    ----------------------------------------------------------------------
    MERGE dbo.ManipOR WITH (UPDLOCK, HOLDLOCK) AS tgt 
    USING (
        SELECT BranchCode, MachineUsed, ReferenceNo, CashierTransNo, SequenceNumber,
               NewQty, NewTotalAmount
        FROM @Items
        WHERE BranchCode = @brcode
          AND MachineUsed = @machinename
          AND Petsa = @petsa
    ) AS src
    ON  tgt.BranchCode     = src.BranchCode
    AND tgt.MachineUsed    = src.MachineUsed
    AND tgt.ReferenceNo    = src.ReferenceNo
    AND tgt.CashierTransNo = src.CashierTransNo
    AND tgt.SequenceNumber = src.SequenceNumber
    WHEN MATCHED THEN
        UPDATE SET tgt.NewQty = src.NewQty, tgt.NewTotalAmount = src.NewTotalAmount
    WHEN NOT MATCHED THEN
        INSERT (BranchCode, ReferenceNo, CashierTransNo, MachineUsed, SequenceNumber, NewQty, NewTotalAmount)
        VALUES (src.BranchCode, src.ReferenceNo, src.CashierTransNo, src.MachineUsed, src.SequenceNumber, src.NewQty, src.NewTotalAmount);

    ----------------------------------------------------------------------
    -- (B) Apply edits to BatchSalesDetails2 (set-based)
    -- Your existing SQL updates via join to ManipOR already does this idea, but
    -- your current approach still depends on app-side row inserts and CAST filters. [3](https://onedrive.live.com/?id=4fbc8d29-e9f5-20f0-80c2-57fb01000000&cid=c2f0e9f54fbc8d29&web=1)[2](https://onedrive.live.com/?id=4fbc8d29-e9f5-20f0-80c2-c37500000000&cid=c2f0e9f54fbc8d29&web=1)
    ----------------------------------------------------------------------
    UPDATE b
        SET b.QtySold     = i.NewQty,
            b.TotalAmount = i.NewTotalAmount,
            b.SubTotal    = i.NewTotalAmount,
            b.isCosting   = 0
    FROM dbo.BatchSalesDetails2 AS b
    INNER JOIN @Items AS i
        ON  b.BranchCode     = i.BranchCode
        AND b.MachineUsed    = i.MachineUsed
        AND b.ReferenceNo    = i.ReferenceNo
        AND b.CashierTransNo = i.CashierTransNo
        AND b.SequenceNumber = i.SequenceNumber
    WHERE b.BranchCode   = @brcode
      AND b.MachineUsed  = @machinename
      AND b.DateOrder   >= @petsa
      AND b.DateOrder   <  @ToDate;

    ----------------------------------------------------------------------
    -- (C) Recompute BatchSalesSummary2 in ONE pass
    ----------------------------------------------------------------------
    ;WITH d AS
    (
        SELECT
            BranchCode, MachineUsed, ReferenceNo,
            COUNT(*) AS TotalItem,
            SUM(CASE WHEN Status='SOLD' AND isConfirmed=1 AND TotalAmount<>0 THEN 1 ELSE 0 END) AS TotalItemSold,
            SUM(CASE WHEN isConfirmed=1 THEN SubTotal ELSE 0 END) AS SubTotal,
            SUM(CASE WHEN Status='SOLD' AND isConfirmed=1 THEN TotalAmount ELSE 0 END) AS TotalAmount,
            SUM(CASE WHEN Status='SOLD' AND isConfirmed=1 AND isVat=0 THEN SubTotal ELSE 0 END) AS TotalVATExemptSale,
            SUM(CASE WHEN Status='SOLD' AND isConfirmed=1 AND isVat=1 THEN SubTotal ELSE 0 END) AS VatSubTotal
        FROM dbo.BatchSalesDetails2
        WHERE BranchCode  = @brcode
          AND MachineUsed = @machinename
          AND DateOrder  >= @petsa AND DateOrder < @ToDate
        GROUP BY BranchCode, MachineUsed, ReferenceNo
    )
    UPDATE s
        SET s.TotalItem          = d.TotalItem,
            s.TotalItemSold      = d.TotalItemSold,
            s.SubTotal           = d.SubTotal,
            s.TotalAmount        = d.TotalAmount,
            s.TotalVATExemptSale = d.TotalVATExemptSale,
            s.TotalVatableSale   = CASE WHEN d.VatSubTotal = 0 THEN 0 ELSE d.VatSubTotal / 1.12 END,
            s.TotalVATSale       = CASE WHEN d.VatSubTotal = 0 THEN 0 ELSE (d.VatSubTotal / 1.12) * 0.12 END
    FROM dbo.BatchSalesSummary2 AS s
    INNER JOIN d
        ON s.BranchCode  = d.BranchCode
       AND s.MachineUsed = d.MachineUsed
       AND s.ReferenceNo = d.ReferenceNo
    WHERE s.BranchCode  = @brcode
      AND s.MachineUsed = @machinename
      AND s.TransDate  >= @petsa AND s.TransDate < @ToDate;

    ----------------------------------------------------------------------
    -- (D) Recompute SalesTransactionSummary2 in ONE update
    ----------------------------------------------------------------------
    ;WITH t AS
    (
        SELECT
            BranchCode, MachineUsed, CashierTransNo,
            SUM(TotalItemSold) AS NoOfSoldItem,
            SUM(TotalAmount) AS TotalSoldItem,
            SUM(SubTotal) AS TotalSales,
            SUM(TotalAmount) AS TotalNetSales,
            SUM(TotalVATExemptSale) AS TotalVatExemptSales,
            SUM(TotalVatableSale) AS TotalVatableSales,
            SUM(TotalVATSale) AS TotalVatAmount,
            SUM(CASE WHEN PaymentType='Cash' THEN TotalAmount ELSE 0 END) AS TotalCashSales,
            SUM(CASE WHEN PaymentType='Credit' THEN TotalAmount ELSE 0 END) AS TotalCreditSales
        FROM dbo.BatchSalesSummary2
        WHERE BranchCode  = @brcode
          AND MachineUsed = @machinename
          AND TransDate  >= @petsa AND TransDate < @ToDate
          AND Status='SOLD'
          AND isFloat=0
        GROUP BY BranchCode, MachineUsed, CashierTransNo
    )
    UPDATE x
        SET x.NoOfSoldItem        = t.NoOfSoldItem,
            x.TotalSoldItem       = t.TotalSoldItem,
            x.TotalSales          = t.TotalSales,
            x.TotalNetSales       = t.TotalNetSales,
            x.TotalVatExemptSales = t.TotalVatExemptSales,
            x.TotalVatableSales   = t.TotalVatableSales,
            x.TotalVatAmount      = t.TotalVatAmount,
            x.TotalCashSales      = t.TotalCashSales,
            x.TotalCreditSales    = t.TotalCreditSales
    FROM dbo.SalesTransactionSummary2 AS x
    INNER JOIN t
        ON x.BranchCode     = t.BranchCode
       AND x.MachineUsed    = t.MachineUsed
       AND x.CashierTransNo = t.CashierTransNo
    WHERE x.BranchCode  = @brcode
      AND x.MachineUsed = @machinename
      AND x.DateOpen    = @petsa;

    ----------------------------------------------------------------------
    -- (E) Refresh POSSalesSummary2 (delete+insert sargable)
    -- This replaces the current delete/insert that uses CAST(DateOrder as date). [2](https://onedrive.live.com/?id=4fbc8d29-e9f5-20f0-80c2-c37500000000&cid=c2f0e9f54fbc8d29&web=1)[3](https://onedrive.live.com/?id=4fbc8d29-e9f5-20f0-80c2-57fb01000000&cid=c2f0e9f54fbc8d29&web=1)
    ----------------------------------------------------------------------
    DELETE dbo.POSSalesSummary2
    WHERE BranchCode = @brcode
      AND MachineUsed = @machinename
      AND DateOrder >= @petsa AND DateOrder < @ToDate;

    INSERT dbo.POSSalesSummary2
    (
        BranchCode, ProductCode, Description, Category, ProcessedBy,
        QtySold, Subtotal, TotalAmount, Status, isVat, DateOrder,
        isUpload, MachineUsed, Cost
    )
    SELECT
        LTRIM(RTRIM(a.BranchCode)),
        LTRIM(RTRIM(a.ProductCode)),
        LTRIM(RTRIM(a.Description)),
        LTRIM(RTRIM(pc.Description)) AS Category,
        LTRIM(RTRIM(a.ProcessedBy)),
        SUM(a.QtySold),
        SUM(a.SubTotal),
        SUM(a.TotalAmount),
        LTRIM(RTRIM(a.Status)),
        pc.isVat,
        @petsa,
        0,
        LTRIM(RTRIM(a.MachineUsed)),
        0
    FROM dbo.BatchSalesDetails2 AS a
    LEFT JOIN dbo.ProductCategory AS pc
        ON a.CategoryCode = pc.ProductCategoryID
    WHERE a.BranchCode  = @brcode
      AND a.MachineUsed = @machinename
      AND a.DateOrder  >= @petsa AND a.DateOrder < @ToDate
      AND a.Status='SOLD'
      AND a.isConfirmed=1
    GROUP BY
        a.BranchCode, a.ProductCode, a.Description, pc.Description, pc.isVat,
        a.ProcessedBy, a.Status, a.MachineUsed;
	
	----------------------------------------------------------------------
    -- (F) Recompute POSZReadingTransactions2  ✅ MISSING PIECE
    ----------------------------------------------------------------------

    DECLARE 
        @prevZDate date,
        @prevEndingBalance money;

    -- Get previous Z-reading date
    SELECT TOP (1)
        @prevZDate = DateExecute,
        @prevEndingBalance = EndingBalance
    FROM dbo.POSZReadingTransactions2
    WHERE BranchCode = @brcode
      AND MachineUsed = @machinename
      AND DateExecute < @petsa
    ORDER BY DateExecute DESC;

    -- Aggregate SalesTransactionSummary2 for the Z day
    ;WITH zAgg AS
    (
        SELECT
            BranchCode,
            MachineUsed,
            SUM(NoOfSoldItem)        AS SoldItems,
            SUM(TotalCashSales)     AS TotalCashSales,
            SUM(TotalCreditSales)   AS TotalCreditSales,
            SUM(TotalSales)         AS TotalSales,
            SUM(TotalVatExemptSales) AS VatExemptSale,
            SUM(TotalVatableSales)  AS VatableSale,
            SUM(TotalVatAmount)     AS VatInput,
            SUM(TotalNetSales)      AS TotalNetSales
        FROM dbo.SalesTransactionSummary2
        WHERE BranchCode = @brcode
          AND MachineUsed = @machinename
          AND DateOpen = @petsa
          AND isOpen = '0'
        GROUP BY BranchCode, MachineUsed
    )
    UPDATE z
        SET
            z.SoldItems        = a.SoldItems,
            z.TotalCashSales  = a.TotalCashSales,
            z.TotalCreditSales= a.TotalCreditSales,
            z.TotalSales      = a.TotalSales,
            z.VatExemptSale   = a.VatExemptSale,
            z.VatableSale     = a.VatableSale,
            z.VatInput        = a.VatInput,

            -- ✅ Balance continuity (matches original spman_calculate)
            z.BeginningBalance =
                CASE 
                    WHEN z.BeginningBalance = 0 THEN 0
                    ELSE ISNULL(@prevEndingBalance, 0)
                END,

            z.EndingBalance =
                CASE 
                    WHEN z.BeginningBalance = 0 THEN a.TotalNetSales
                    ELSE ISNULL(@prevEndingBalance, 0) + a.TotalNetSales
                END,

            z.TotalNetSales = a.TotalNetSales
		FROM dbo.POSZReadingTransactions2 z
		INNER JOIN zAgg a
			ON z.BranchCode = a.BranchCode
		   AND z.MachineUsed = a.MachineUsed
		WHERE z.BranchCode = @brcode
		  AND z.MachineUsed = @machinename
		  AND z.DateExecute = @petsa;

		  
			/* ===============================
			   (G) FINAL SUCCESS LOG
			=============================== */
			
			IF NOT EXISTS (
				SELECT 1
				FROM SalesManagement
				WHERE BranchCode = @brcode
				  AND MachineName = @machinename
				  AND SalesDate = @petsa
			)
			BEGIN
				INSERT INTO SalesManagement
			(
				BranchCode,
				MachineName,
				SalesDate,
				DateAdded,
				AddedBy
			)
			VALUES
			(
				@brcode,
				@machinename,
				@petsa,
				GETDATE(),
				'system'
			);
			END

			
		  
		/* ===============================
           SUCCESS
        =============================== */

		COMMIT;
	
	END TRY
    BEGIN CATCH
        /* ===============================
           FAIL SAFE ROLLBACK
        =============================== */
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        DECLARE 
            @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrNum INT = ERROR_NUMBER(),
            @ErrLine INT = ERROR_LINE();

        RAISERROR('spman_apply_and_calculate failed: %s (Err:%d, Line:%d)',
                  16, 1, @ErrMsg, @ErrNum, @ErrLine);
    END CATCH

END

