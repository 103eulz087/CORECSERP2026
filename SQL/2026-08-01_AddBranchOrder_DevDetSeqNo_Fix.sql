/* ============================================================
   Fix: AddBranchOrder.cs "Cancel" line button silently failed to
   refund Inventory.Available, because InventoryDeliveryFIFO.DevDetSeqNo
   was hardcoded to 0 instead of the real DeliveryDetails.SeqNo, so
   sp_CancelDelivery's refund-matching predicate never matched in
   barcode-scanning mode.

   While fixing that, a second defect was found in the same lines:
   sp_AddHRIOrderByBarcode and sp_SalesQtyToInventoryQtyHRI inserted
   only 13 values into InventoryDeliveryFIFO, which needs 15
   (SellingPrice/TotalAmount were added to the table later and these
   procs were never updated) -- causing "Add Item" itself to throw a
   SQL error on any genuinely new line.

   Verified end-to-end against CORECSJFC2026_STAGING on 2026-08-01:
   Add correctly deducts the right Inventory row, the ledger now
   stores the real DevDetSeqNo, and Cancel correctly matches and
   fully restores the quantity.

   Deployment pattern: EXEC sp_rename the current (buggy) procedure
   to <name>_OLD (kept untouched as a rollback reference), then
   CREATE PROCEDURE the fixed version fresh under the original name.
   No ALTER is used, so nothing is silently overwritten.

   Rollback: DROP the new <name>, then
   EXEC sp_rename 'dbo.<name>_OLD', '<name>';

   Run this against production when ready.
   ============================================================ */

SET NOCOUNT ON;

PRINT '=== 1/7 sp_SalesQtyToInventoryQtyHRI ===';
GO
EXEC sp_rename 'dbo.sp_SalesQtyToInventoryQtyHRI', 'sp_SalesQtyToInventoryQtyHRI_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_SalesQtyToInventoryQtyHRI]
	@parmSeqNo bigint
	,@parmorigin char(3)
	,@parmBranch char(3)
	,@parmProduct char(5)
	,@parmRunningQtySold float
	,@parmsellingprice money
	,@parmdevno varchar(10)
	,@parmpono varchar(10)
	,@TotalCost float output
	,@parmDevDetSeqNo int = 0

AS
BEGIN
	DECLARE @iSeqNo bigint, @iQty float, @iAvailable float, @iCost float;
	DECLARE @ProductDescription varchar(max), @Unit varchar(255);
	DECLARE @RunningQtySold float=@parmRunningQtySold;

	WHILE(0<@RunningQtySold)
	BEGIN
		SET @iSeqNo = null; -- use to break a loop;
		-- LINK SERVER
		UPDATE TOP(1) Inventory
		SET @iSeqNo=SequenceNumber,
			@iQty=ISNULL(Available, Quantity),
			@iAvailable=IIF(@RunningQtySold>=@iQty, 0, @iQty-@RunningQtySold),
			@iCost=ISNULL(Cost, 0),
			--
			--@Unit=Unit,
			@ProductDescription=Description,
			-- update
			Available=@iAvailable
		WHERE ISNULL(Available, Quantity)>0 AND (Branch=@parmBranch AND Product =@parmProduct) ;
		IF(@iSeqNo IS NULL)BREAK; -- break loop
		---- To Ledger
		INSERT INTO InventoryDeliveryFIFO --select * FROM InventoryDeliveryFIFO where PONumber=176
		VALUES(@parmdevno,@parmpono,@parmBranch,@parmProduct,@ProductDescription,(@iQty-@iAvailable),@iCost,((@iQty-@iAvailable)*@iCost),GETDATE(),@iSeqNo,@parmDevDetSeqNo,0,0,ISNULL(@parmsellingprice,0),((@iQty-@iAvailable)*ISNULL(@parmsellingprice,0)))

		INSERT INTO InventoryLedger
		VALUES(@iSeqNo,@parmorigin,@parmBranch,GETDATE(),@parmProduct,@ProductDescription,@iQty,0,(@iQty-@iAvailable),@iAvailable,@iCost,'STS IN-TRANSIT PO#-'+@parmpono,'System')
		-- LINK SERVER END --
		SET @RunningQtySold=(@RunningQtySold-@iQty);
		SET @TotalCost+=(@iCost*(@iQty-@iAvailable));
	END;

	-- returns
	--SELECT @TotalCost AS TotalCost;
END;
GO

PRINT '=== 2/7 sp_SalesQtyToInventoryQtyHRI_JFC ===';
GO
EXEC sp_rename 'dbo.sp_SalesQtyToInventoryQtyHRI_JFC', 'sp_SalesQtyToInventoryQtyHRI_JFC_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_SalesQtyToInventoryQtyHRI_JFC]
	@parmSeqNo bigint
	,@parmorigin char(3)
	,@parmBranch char(3)
	,@parmshipmentno varchar(10)
	,@parmProduct char(5)
	,@parmRunningQtySold float
	,@parmsellingprice money
	,@parmdevno varchar(10)
	,@parmpono varchar(10)
	,@TotalCost float output
	,@parmDevDetSeqNo int = 0

AS
BEGIN
	DECLARE @iSeqNo bigint, @iQty float, @iAvailable float, @iCost float;
	DECLARE @ProductDescription varchar(max), @Unit varchar(255);
	DECLARE @RunningQtySold float=@parmRunningQtySold;

	WHILE(0<@RunningQtySold)
	BEGIN
		SET @iSeqNo = null; -- use to break a loop;
		-- LINK SERVER
		UPDATE TOP(1) Inventory
		SET @iSeqNo=SequenceNumber,
			@iQty=ISNULL(Available, Quantity),
			@iAvailable=IIF(@RunningQtySold>=@iQty, 0, @iQty-@RunningQtySold),
			@iCost=ISNULL(Cost, 0),
			--
			--@Unit=Unit,
			@ProductDescription=Description,
			-- update
			Available=@iAvailable
		WHERE ISNULL(Available, Quantity)>0 AND (ShipmentNo=@parmshipmentno and Branch=@parmBranch AND Product =@parmProduct) ;
		IF(@iSeqNo IS NULL)BREAK; -- break loop
		---- To Ledger
		INSERT INTO InventoryDeliveryFIFO --select * FROM InventoryDeliveryFIFO where PONumber=176 alter table InventoryDeliveryFIFO add SellingPrice decimal(18,2)
		VALUES(@parmdevno,@parmpono,@parmBranch,@parmProduct,@ProductDescription,(@iQty-@iAvailable),@iCost,((@iQty-@iAvailable)*@iCost),GETDATE(),@iSeqNo,@parmDevDetSeqNo,0,0,@parmsellingprice,((@iQty-@iAvailable)*@parmsellingprice))

		INSERT INTO InventoryLedger
		VALUES(@iSeqNo,@parmorigin,@parmBranch,GETDATE(),@parmProduct,@ProductDescription,@iQty,0,(@iQty-@iAvailable),@iAvailable,@iCost,'STS IN-TRANSIT PO#-'+@parmpono,'System')
		-- LINK SERVER END --
		SET @RunningQtySold=(@RunningQtySold-@iQty);
		SET @TotalCost+=(@iCost*(@iQty-@iAvailable));
	END;

	-- returns
	--SELECT @TotalCost AS TotalCost;
END;
GO

PRINT '=== 3/7 sp_AddHRIOrderByBarcode ===';
GO
EXEC sp_rename 'dbo.sp_AddHRIOrderByBarcode', 'sp_AddHRIOrderByBarcode_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_AddHRIOrderByBarcode]
    @parmdevno       VARCHAR(20),
    @parmrefno       VARCHAR(10),
    @parmpono        VARCHAR(10),
    @parmbarcode     VARCHAR(100),
    @parmbranchcode  VARCHAR(10),
    @parmorigin      VARCHAR(10),
    @preparedby      VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE
            @parmeffectivitydate DATE,
            @invqty FLOAT,
            @invprodcode VARCHAR(10),
            @invprodname VARCHAR(150),
            @invcost MONEY,
            @invisvat BIT,
            @invSeqNo BIGINT,    -- primary key/SequenceNumber in Inventory (assumes it exists)
            @custkey CHAR(8),
            @specialpriceamount MONEY,
            @devseqno INT;

        /* 1) Get EffectivityDate once */
        SELECT @parmeffectivitydate = s.EffectivityDate
        FROM dbo.PurchaseOrderSummary AS s WITH (READCOMMITTED)
        WHERE s.PONumber = @parmpono;

        /* 2) Get exactly one matching Inventory row (by barcode in origin branch, warehouse stock, available > 0)
              Use a deterministic order; SequenceNumber ASC = FIFO */
        SELECT TOP (1)
            @invqty      = inv.Available,
            @invprodcode = inv.Product,
            @invprodname = inv.Description,
            @invcost     = inv.Cost,
            @invisvat    = inv.IsVat,
            @invSeqNo    = inv.SequenceNumber
        FROM dbo.Inventory AS inv WITH (UPDLOCK, ROWLOCK)   -- lock the chosen row for update
        WHERE inv.Branch = @parmorigin
          AND inv.IsWarehouse = 1
          AND inv.Available > 0
          AND inv.Barcode = @parmbarcode
        ORDER BY inv.SequenceNumber ASC;--select * FROM PurchaseOrderDetails

		IF NOT EXISTS (SELECT TOP(1) 1 FROM dbo.PurchaseOrderDetails WHERE PONumber=@parmpono and ProductCode=@invprodcode)
		BEGIN
			-- Nothing found for that barcode in origin's warehouse
            RAISERROR('This Product is not Available in the the Request %s.', 16, 1, @parmbarcode, @parmorigin);

        END

		--IF (@invqty=0)
		--BEGIN
		--	update Inventory set Available=Quantity, IsWarehouse=1,isStock=0,ReferenceCode='upd0qty' WHERE Barcode=@parmbarcode and Branch='888'

		--END
        IF (@invSeqNo IS NULL)
        BEGIN

			--update Inventory set Available=Quantity, IsWarehouse=1,isStock=0,ReferenceCode='updnull' WHERE Barcode=@parmbarcode and Branch='888'
            -- Nothing found for that barcode in origin's warehouse
            RAISERROR('No available warehouse inventory found for barcode %s in origin %s.', 16, 1, @parmbarcode, @parmorigin);

        END

        /* 4) Generate next SeqNo for this DeliveryNo + PO under lock
              Use a dummy key lock to serialize sequence per header */
        -- Lock the header scope for this pair to avoid duplicates when multiple rows insert concurrently
        -- If you have a DeliveryHeader table, UPDLOCK it here; else use sp_getapplock:

		DECLARE @seqLockResource NVARCHAR(256);
		SET @seqLockResource = N'DeliveryDetailsSeq_' + CAST(@parmdevno AS NVARCHAR(50)) + N'_' + CAST(@parmpono AS NVARCHAR(50));

		DECLARE @applockResult INT;

		-- Acquire exclusive lock for this (DeliveryNo, PONumber) to serialize SeqNo allocation
		EXEC @applockResult = sys.sp_getapplock
			 @Resource     = @seqLockResource,
			 @LockMode     = 'Exclusive',
			 @LockTimeout  = 10000,       -- 10s; adjust as needed
			 @DbPrincipal  = 'dbo';

		IF (@applockResult < 0)
		BEGIN
			RAISERROR('Unable to acquire sequence lock for Delivery %s / PO %s.', 16, 1, @parmdevno, @parmpono);
		END

		-- Safely compute next SeqNo under lock
		SELECT @devseqno = ISNULL(MAX(d.SeqNo), 0)
		FROM dbo.DeliveryDetails AS d WITH (UPDLOCK, HOLDLOCK)
		WHERE d.DeliveryNo = @parmdevno
		  AND d.PONumber   = @parmpono;

		SET @devseqno = @devseqno + 1;

         -- Cross-branch: default to product price at origin (existing behavior fallback)
            SELECT @specialpriceamount = p.SellingPrice
            FROM dbo.Products AS p WITH (READCOMMITTED)
            WHERE p.ProductCode = @invprodcode
              AND p.BranchCode = @parmorigin;

        /* 5) Insert DeliveryDetails if not yet present for this barcode */

        -- Using UPDLOCK, HOLDLOCK prevents C# double-click race conditions!
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.DeliveryDetails WITH (UPDLOCK, HOLDLOCK)
            WHERE DeliveryNo = @parmdevno
              AND PONumber = @parmpono
              AND BarcodeNo = @parmbarcode
        )
        BEGIN
            -- 1. Insert the Delivery Line
            INSERT INTO dbo.DeliveryDetails
            (
                SeqNo, DeliveryNo, PONumber, ReferenceNumber,
                ProductNo, BarcodeNo, ProductName,
                QtyDelivered, ActualQty, Variance,
                Cost, SellingPrice, [Status], isVat,
                ProcessedBy, isSettled, isCreditMemo, isReturned
            )
            VALUES
            (
                @devseqno, @parmdevno, @parmpono, @parmrefno,
                @invprodcode, @parmbarcode, @invprodname,
                @invqty, @invqty, 0,
                @invcost, ISNULL(@specialpriceamount, 0), 'PENDING', @invisvat,
                @preparedby, 0, 0, 0
            );

            -- 2. Zero out the inventory (SAFELY INSIDE THE BLOCK)
            UPDATE dbo.Inventory
            SET Available = 0
            WHERE SequenceNumber = @invSeqNo;

            ---- To Ledger
            IF NOT EXISTS(SELECT 1 FROM InventoryDeliveryFIFO WHERE SequenceReferenceNumber=@invSeqNo and isErrorCorrect=0)
            BEGIN
		        INSERT INTO InventoryDeliveryFIFO --select * FROM InventoryDeliveryFIFO where PONumber=176
		        VALUES(@parmdevno,@parmpono,@parmbranchcode,@invprodcode,@invprodname,@invqty,@invcost,(@invqty*@invcost),GETDATE(),@invSeqNo,@devseqno,0,0,ISNULL(@specialpriceamount,0),(@invqty*ISNULL(@specialpriceamount,0)))
            END

        END
        -- else: already present; silent no-op (idempotent)

        -- Release applock
       	-- Release the applock after you're done with the sequence and insert
		EXEC sys.sp_releaseapplock @Resource = @seqLockResource, @DbPrincipal = 'dbo';

        /* 6) Upsert DeliverySummary (if not exists  insert; else update totals) */
        DECLARE
            @totalitem INT,
            @totalqtydelivered FLOAT;

        SELECT
            @totalitem = COUNT(*),
            @totalqtydelivered = ISNULL(SUM(d.QtyDelivered), 0)
        FROM dbo.DeliveryDetails AS d WITH (READCOMMITTED)
        WHERE d.DeliveryNo = @parmdevno
          AND d.PONumber = @parmpono;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.DeliverySummary WITH (READCOMMITTED)
            WHERE PONumber = @parmpono
              AND DeliveryNo = @parmdevno
        )
        BEGIN
            INSERT INTO dbo.DeliverySummary
            (
                DeliveryNo, PONumber, ReferenceNumber, InvoiceNo,
                BranchCode, TotalItem, TotalQtyDelivered, TotalActualQty,
                TotalVarianceVat, TotalVarianceVatExempt, EffectivityDate,
                [Status], DateAdded, PreparedBy, isSettled, isInvoiceUpdate
            )
            VALUES
            (
                @parmdevno, @parmpono, @parmrefno, @parmrefno,
                @parmbranchcode, @totalitem, @totalqtydelivered, 0,
                0, 0, ISNULL(@parmeffectivitydate, GETDATE()),
                'PENDING', GETDATE(), @preparedby, 0, 0
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.DeliverySummary
            SET TotalItem         = @totalitem,
                TotalQtyDelivered = @totalqtydelivered,
                -- keep other totals as-is or recompute if that's the rule
                EffectivityDate   = ISNULL(@parmeffectivitydate, EffectivityDate),
                DateAdded         = DateAdded, -- leave original created date
                PreparedBy        = PreparedBy -- leave as is
            WHERE PONumber = @parmpono
              AND DeliveryNo = @parmdevno;
        END

        COMMIT TRAN;

        -- Return a compact status payload
        SELECT
            1     AS [status],
            'OK'  AS [message],
            @devseqno AS NextSeqNoUsed,
            @invprodcode AS ProductCode,
            @invprodname AS ProductName,
            @invqty AS QtyDelivered;

    END TRY
    BEGIN CATCH
        IF (XACT_STATE()) <> 0 ROLLBACK TRAN;

        DECLARE @errMsg NVARCHAR(4000) = ERROR_MESSAGE(),
                @errNo  INT            = ERROR_NUMBER(),
                @errSev INT            = ERROR_SEVERITY(),
                @errSta INT            = ERROR_STATE(),
                @errLin INT            = ERROR_LINE();

        RAISERROR('[sp_AddBranchOrderByBarcode] failed: %s (Err %d, Sev %d, State %d, Line %d)',
                  @errSev, 1, @errMsg, @errNo, @errSev, @errSta, @errLin);

        SELECT 2 AS [status], 'Error' AS [message], @errNo AS ErrorNumber, @errMsg AS ErrorMessage;
    END CATCH
END
GO

PRINT '=== 4/7 sp_FiFoMappingHRI ===';
GO
EXEC sp_rename 'dbo.sp_FiFoMappingHRI', 'sp_FiFoMappingHRI_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_FiFoMappingHRI]  --CREATE  exec sp_FiFoMappingSTS '5/3/2025','888','005','12931',10,'576700','450338'
	@parmtransdate date
	,@parmorigin char(3)
	,@parmbranchcode char(3)
	,@parmprodcode char(5)
	,@parmqty float
	,@parmdevno varchar(10)
	,@parmpono varchar(10)
	,@parmdevseqno int = 0
AS
BEGIN
	-- example
	--exec sp_FiFoMapping '01/31/2020','001','','','2';  for All
	--exec.sp_FiFo5 '','001','00008','10','1';  for Single Product

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT OFF;
	BEGIN TRAN
	----------------------------------------------------
	DECLARE @SeqNo bigint=null, @Branch char(3), @DateOrder date, @ParentProduct char(5), @ChildProduct char(5), @QtyBase float, @QtySold float, @ChildStatus int;
	DECLARE @TotalCost float, @RunningQtySold float, @TotalCostOverQtySold float;
	DECLARE @iSeqNo bigint, @iQty float, @iAvailable float, @iCost float;
	DECLARE @I int, @rowno int, @rownoStart int, @productcnt int; -- this is for LOOP
	-- START --------------------------------------------------

	DECLARE @tblSalesSummary TABLE(
		rowno int identity,
		SeqNo bigint NULL,
		Branch [char](3) NULL,
		DateOrder [date] NULL,
		--
		ParentProduct [char](5) NULL,
		ChildProduct [char](5) NULL,
		QtyBase [float] NULL,
		QtySold [float] NULL,
		TempCost [float] NULL,
		-- Only for temporary
		--HasChild [int] NULL,
		IsTemp [int] NULL
	);


	INSERT INTO @tblSalesSummary(SeqNo,  Branch, ParentProduct, QtySold, IsTemp)
	SELECT 0, @parmbranchcode, @parmprodcode, @parmqty, 1;

	SET @rownoStart=(@@ROWCOUNT + 1); -- Get Rows

	;WITH cte AS(
		SELECT ss.*, IIF(im.min IS NULL, 0, 1) haschild
		FROM @tblSalesSummary ss
		LEFT JOIN(
			SELECT ParentProductCode, MIN(ChildProductCode) min
			FROM InventoryMapping im with(nolock)
			WHERE ParentProductCode IS NOT NULL
			GROUP BY ParentProductCode
		) im ON im.ParentProductCode=ss.ParentProduct
	)

	INSERT INTO @tblSalesSummary
	(SeqNo, Branch,  DateOrder, ParentProduct, ChildProduct, QtyBase, QtySold)
	SELECT * FROM (
					SELECT SeqNo, Branch, DateOrder, ParentProduct, null as ChildProduct, null as QtyBase, QtySold as QtySold
					FROM cte WHERE haschild=0
					UNION ALL
					SELECT ss.SeqNo, ss.Branch, ss.DateOrder, ss.ParentProduct, im.ChildProductCode, im.Quantity, ss.QtySold as QtySold
					FROM InventoryMapping im
					LEFT JOIN (SELECT * FROM cte  with(nolock) WHERE haschild=1) ss
					ON ss.ParentProduct=im.ParentProductCode
					WHERE (im.ParentProductCode IS NOT NULL AND ss.SeqNo IS NOT NULL)
	)r ORDER BY SeqNo

	DELETE FROM @tblSalesSummary WHERE ISNULL(IsTemp,0)=1

	DECLARE @sprice decimal(10,2)
	DECLARE @LastSeqNo bigint = null;
	SET @rowno=0; SET @I=@rownoStart;
	SET @productcnt=0; SET @ChildStatus=0;
	WHILE (@rowno IS NOT NULL)
	BEGIN
		SET @TotalCost = 0.00;
		IF(ISNULL(@rowno,0)<>0 AND @ChildStatus=0)
		BEGIN
			DECLARE @ProductDescription varchar(max), @Unit varchar(255);
			SET @RunningQtySold = (IIF(@ChildProduct IS NULL, 1, @QtyBase) * @QtySold); -- @QtySold;
			SET @ChildProduct=ISNULL(@ChildProduct, @ParentProduct);
			select TOP 1 @sprice=SellingPrice FROM Products  with(nolock) WHERE BranchCode=@Branch and ProductCode=@ChildProduct
			exec dbo.sp_SalesQtyToInventoryQtyHRI @SeqNo, @parmorigin,@parmbranchcode, @ChildProduct, @RunningQtySold,@sprice,@parmdevno,@parmpono, @TotalCost output, @parmDevDetSeqNo=@parmdevseqno;

			SET @LastSeqNo=@SeqNo; SET @productcnt+=1;
			-- update temp cost
			UPDATE TOP(1) @tblSalesSummary
			SET TempCost=@TotalCost
			WHERE(rowno=@rowno);
		END;

		SET @rowno=null; SET @SeqNo=null;  -- use to break a loop;
		SELECT TOP(1) @rowno=rowno --loop
			,@SeqNo=SeqNo
			,@Branch=Branch
			,@DateOrder=DateOrder
			,@ParentProduct=ParentProduct
			,@ChildProduct=ChildProduct
			,@QtyBase=ISNULL(QtyBase, 0)
			,@QtySold=ISNULL(QtySold, 0)
		FROM @tblSalesSummary WHERE(rowno=@I); --loop
		IF(ISNULL(@LastSeqNo, @SeqNo)<>ISNULL(@SeqNo, 0))
		BEGIN
			-- SET Special
			SET @productcnt=0;
		END;
		IF(@rowno IS NULL)BREAK;-- break loop
		SET @I+=1; -- Use for Increment Row of @tblSalesSummary
	END;


	COMMIT TRAN

END;
GO

PRINT '=== 5/7 sp_FiFoMappingHRI_JFC ===';
GO
EXEC sp_rename 'dbo.sp_FiFoMappingHRI_JFC', 'sp_FiFoMappingHRI_JFC_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_FiFoMappingHRI_JFC]  --CREATE  exec sp_FiFoMappingSTS '5/3/2025','888','005','12931',10,'576700','450338'
	@parmtransdate date
	,@parmorigin char(3)
	,@parmbranchcode char(3)
	,@parmprodcode char(5)
	,@parmshipmentno varchar(10)
	,@parmqty float
	,@parmsellingprice decimal(12,2)
	,@parmdevno varchar(10)
	,@parmpono varchar(10)
	,@parmdevseqno int = 0
AS
BEGIN
	-- example
	--exec sp_FiFoMapping '01/31/2020','001','','','2';  for All
	--exec.sp_FiFo5 '','001','00008','10','1';  for Single Product

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT OFF;
	BEGIN TRAN
	----------------------------------------------------
	DECLARE @SeqNo bigint=null, @Branch char(3), @DateOrder date, @ParentProduct char(5), @ChildProduct char(5), @QtyBase float, @QtySold float, @ChildStatus int;
	DECLARE @TotalCost float, @RunningQtySold float, @TotalCostOverQtySold float;
	DECLARE @iSeqNo bigint, @iQty float, @iAvailable float, @iCost float;
	DECLARE @I int, @rowno int, @rownoStart int, @productcnt int; -- this is for LOOP
	-- START --------------------------------------------------

	DECLARE @tblSalesSummary TABLE(
		rowno int identity,
		SeqNo bigint NULL,
		Branch [char](3) NULL,
		ShipmentNo [varchar](10) NULL,
		DateOrder [date] NULL,
		--
		ParentProduct [char](5) NULL,
		ChildProduct [char](5) NULL,
		QtyBase [float] NULL,
		QtySold [float] NULL,
		TempCost [float] NULL,
		-- Only for temporary
		--HasChild [int] NULL,
		IsTemp [int] NULL
	);


	INSERT INTO @tblSalesSummary(SeqNo,  Branch,ShipmentNo ,ParentProduct, QtySold, IsTemp)
	SELECT 0, @parmbranchcode,@parmshipmentno, @parmprodcode, @parmqty, 1;

	SET @rownoStart=(@@ROWCOUNT + 1); -- Get Rows

	;WITH cte AS(
		SELECT ss.*, IIF(im.min IS NULL, 0, 1) haschild
		FROM @tblSalesSummary ss
		LEFT JOIN(
			SELECT ParentProductCode, MIN(ChildProductCode) min
			FROM InventoryMapping im with(nolock)
			WHERE ParentProductCode IS NOT NULL
			GROUP BY ParentProductCode
		) im ON im.ParentProductCode=ss.ParentProduct
	)

	INSERT INTO @tblSalesSummary
	(SeqNo, Branch,  DateOrder, ParentProduct, ChildProduct, QtyBase, QtySold)
	SELECT * FROM (
					SELECT SeqNo, Branch, DateOrder, ParentProduct, null as ChildProduct, null as QtyBase, QtySold as QtySold
					FROM cte WHERE haschild=0
					UNION ALL
					SELECT ss.SeqNo, ss.Branch, ss.DateOrder, ss.ParentProduct, im.ChildProductCode, im.Quantity, ss.QtySold as QtySold
					FROM InventoryMapping im
					LEFT JOIN (SELECT * FROM cte  with(nolock) WHERE haschild=1) ss
					ON ss.ParentProduct=im.ParentProductCode
					WHERE (im.ParentProductCode IS NOT NULL AND ss.SeqNo IS NOT NULL)
	)r ORDER BY SeqNo

	DELETE FROM @tblSalesSummary WHERE ISNULL(IsTemp,0)=1

	--DECLARE @sprice decimal(10,2)
	DECLARE @LastSeqNo bigint = null;
	SET @rowno=0; SET @I=@rownoStart;
	SET @productcnt=0; SET @ChildStatus=0;
	WHILE (@rowno IS NOT NULL)
	BEGIN
		SET @TotalCost = 0.00;
		IF(ISNULL(@rowno,0)<>0 AND @ChildStatus=0)
		BEGIN
			DECLARE @ProductDescription varchar(max), @Unit varchar(255);
			SET @RunningQtySold = (IIF(@ChildProduct IS NULL, 1, @QtyBase) * @QtySold); -- @QtySold;
			SET @ChildProduct=ISNULL(@ChildProduct, @ParentProduct);
			--select TOP 1 @sprice=SellingPrice FROM Products  with(nolock) WHERE BranchCode=@Branch and ProductCode=@ChildProduct
			exec dbo.sp_SalesQtyToInventoryQtyHRI_JFC @SeqNo, @parmorigin,@parmbranchcode,@parmshipmentno, @ChildProduct, @RunningQtySold,@parmsellingprice,@parmdevno,@parmpono, @TotalCost output, @parmDevDetSeqNo=@parmdevseqno;

			SET @LastSeqNo=@SeqNo; SET @productcnt+=1;
			-- update temp cost
			UPDATE TOP(1) @tblSalesSummary
			SET TempCost=@TotalCost
			WHERE(rowno=@rowno);
		END;

		SET @rowno=null; SET @SeqNo=null;  -- use to break a loop;
		SELECT TOP(1) @rowno=rowno --loop
			,@SeqNo=SeqNo
			,@Branch=Branch
			,@DateOrder=DateOrder
			,@ParentProduct=ParentProduct
			,@ChildProduct=ChildProduct
			,@QtyBase=ISNULL(QtyBase, 0)
			,@QtySold=ISNULL(QtySold, 0)
		FROM @tblSalesSummary WHERE(rowno=@I); --loop
		IF(ISNULL(@LastSeqNo, @SeqNo)<>ISNULL(@SeqNo, 0))
		BEGIN
			-- SET Special
			SET @productcnt=0;
		END;
		IF(@rowno IS NULL)BREAK;-- break loop
		SET @I+=1; -- Use for Increment Row of @tblSalesSummary
	END;


	COMMIT TRAN

END;
GO

PRINT '=== 6/7 sp_AddBranchOrderHRI ===';
GO
EXEC sp_rename 'dbo.sp_AddBranchOrderHRI', 'sp_AddBranchOrderHRI_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_AddBranchOrderHRI]
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmpono varchar(10),
	@parmprodcatcode varchar(10),
	@parmprodcode varchar(10),
	@parmqty decimal(18,3), -- Using Decimal instead of Float
	@parmbarcode varchar(50),
	@parmbranchcode varchar(10),
	@parmorigin varchar(10),
	@preparedby varchar(30),
	@parmsourceseqno varchar(20),
	@parmbarcodescanning bit
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		BEGIN TRAN;

		DECLARE @productname varchar(100);
		DECLARE @qtyrequested decimal(18,3) = @parmqty;
		DECLARE @parmeffectivitydate date;
		DECLARE @isvatablenew bit;
		DECLARE @specialpriceamount decimal(18,2);
		DECLARE @custkey char(8);
		DECLARE @devseqno int;
		DECLARE @parminvsettings bit;
		DECLARE @invqty decimal(18,3);

		-- 1. Get Effectivity Date
		SELECT @parmeffectivitydate = EffectivityDate
		FROM TransferOrderSummary
		WHERE PONumber = @parmpono;

		IF @parmeffectivitydate IS NULL
		BEGIN
			SET @parmeffectivitydate = GETDATE(); -- Meaningful fallback
		END

		-- 2. Get Product Info
		SELECT @productname = Description, @isvatablenew = ISNULL(isVat,0)
		FROM Products
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;

		SELECT @invqty = SUM(Available)
		FROM Inventory
		WHERE Branch = @parmorigin AND Available > 0 AND isStock = 1 AND Product = @parmprodcode AND IsWarehouse = 1;

		-- 3. Pricing Logic
		--IF @parmbranchcode = @parmorigin
		--BEGIN
		--	SELECT @custkey = Customer FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

		--	SELECT @specialpriceamount = SpecialPriceAmount FROM CustomerProductSetting
		--	WHERE ProductCode = @parmprodcode AND CustomerKey = @custkey;

		--	IF (@specialpriceamount = 0 OR @specialpriceamount IS NULL)
		--	BEGIN
		--		SELECT @specialpriceamount = SellingPrice FROM Products
		--		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;
		--	END
		--END
		SELECT @specialpriceamount = SellingPrice FROM Products
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;
		-- 4. FIFO Processing & Delivery Details select * FROM InventorySettings
		SELECT @parminvsettings = isFIFO FROM InventorySettings;

		IF @parminvsettings = 1
		BEGIN
			SELECT @devseqno = ISNULL(MAX(SeqNo),0) + 1 FROM DeliveryDetails
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

			-- Execute FIFO Mapping
			EXEC sp_FiFoMappingHRI @parmeffectivitydate, @parmorigin, @parmbranchcode, @parmprodcode, @parmqty, @parmdevno, @parmpono, @parmdevseqno=@devseqno;

			-- Check if FIFO actually generated records (Meaning there was inventory available to deduct)
			IF EXISTS (SELECT TOP 1 DeliveryNo FROM InventoryDeliveryFIFO WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND ProductNo = @parmprodcode)
			BEGIN
				--IF NOT EXISTS (SELECT TOP 1 DeliveryNo FROM DeliveryDetails WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND ProductNo = @parmprodcode)
				--BEGIN
					INSERT INTO [dbo].[DeliveryDetails] (
						[SeqNo], [DeliveryNo], [PONumber], [ReferenceNumber], [ProductNo], [BarcodeNo],
						[ProductName], [QtyDelivered], [ActualQty], [Variance], [Cost], [SellingPrice],
						[Status], [isVat], [ProcessedBy], [isSettled], [isCreditMemo], [isReturned]
					)
					SELECT
						@devseqno, @parmdevno, @parmpono, @parmrefno, @parmprodcode, @parmbarcode,
						@productname, @parmqty, @parmqty, 0, 0, ISNULL(@specialpriceamount,0),
						'PENDING', @isvatablenew, @preparedby, 0, 0, 0;
				--END
			END
			ELSE
			BEGIN
				-- If you want it to insert into DeliveryDetails even if FIFO fails (e.g. out of stock),
				-- you need to add logic here! Currently, if out of stock, it skips inserting the detail.
				PRINT 'No Inventory Available for FIFO deduction. Detail skipped.';
			END
		END

		-- 5. Delivery Summary Logic (FIXED: Changed IF EXISTS to IF NOT EXISTS)
		IF NOT EXISTS (SELECT TOP(1) PONumber FROM DeliverySummary WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno)
		BEGIN
			DECLARE @totalitem int, @totalqtydelivered decimal(18,3);

			SELECT @totalitem = ISNULL(COUNT(*),0), @totalqtydelivered = ISNULL(SUM(QtyDelivered),0)
			FROM DeliveryDetails
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

			INSERT INTO [dbo].[DeliverySummary] (
				[DeliveryNo], [PONumber], [ReferenceNumber], [InvoiceNo], [BranchCode],
				[TotalItem], [TotalQtyDelivered], [TotalActualQty], [TotalVarianceVat], [TotalVarianceVatExempt],
				[EffectivityDate], [Status], [DateAdded], [PreparedBy], [isSettled], [isInvoiceUpdate]
			)
			SELECT
				@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
				@totalitem, @totalqtydelivered, 0, 0, 0,
				@parmeffectivitydate, 'PENDING', GETDATE(), @preparedby, 0, 0;
		END

		COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN;

		-- Force the error to show up in SSMS or your App instead of failing silently
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END
GO

PRINT '=== 7/7 sp_AddBranchOrderHRI_JFC ===';
GO
EXEC sp_rename 'dbo.sp_AddBranchOrderHRI_JFC', 'sp_AddBranchOrderHRI_JFC_OLD';
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE [dbo].[sp_AddBranchOrderHRI_JFC]
	@parmdevno varchar(20),
	@parmrefno varchar(10),
	@parmpono varchar(10),
	@parmprodcatcode varchar(10),
	@parmprodcode varchar(10),
	@parmshipmentno varchar(10),
	--@parmreferencecode varchar(50),
	@parmqty decimal(18,3), -- Using Decimal instead of Float
	@parmbarcode varchar(50),
	@parmbranchcode varchar(10),
	@parmorigin varchar(10),
	@preparedby varchar(30),
	@parmsourceseqno varchar(20),
	@parmbarcodescanning bit
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		BEGIN TRAN;

		DECLARE @productname varchar(100);
		DECLARE @qtyrequested decimal(18,3) = @parmqty;
		DECLARE @parmeffectivitydate date;
		DECLARE @isvatablenew bit;
		DECLARE @specialpriceamount decimal(18,2);
		DECLARE @custkey char(8);
		DECLARE @devseqno int;
		DECLARE @parminvsettings bit;
		DECLARE @invqty decimal(18,3);

		-- 1. Get Effectivity Date
		SELECT @parmeffectivitydate = EffectivityDate
		FROM TransferOrderSummary
		WHERE PONumber = @parmpono;

		IF @parmeffectivitydate IS NULL
		BEGIN
			SET @parmeffectivitydate = GETDATE(); -- Meaningful fallback
		END

		-- 2. Get Product Info
		SELECT @productname = Description, @isvatablenew = ISNULL(isVat,0)
		FROM Products
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;

		SELECT @invqty = SUM(Available)
		FROM Inventory
		WHERE ShipmentNo=@parmshipmentno and Branch = @parmorigin AND Available > 0  AND Product = @parmprodcode;
		-- =========================================================================
		-- ?? THE TRAP: INSUFFICIENT INVENTORY CHECK
		-- =========================================================================
		IF @invqty < @parmqty
		BEGIN
			-- Formats a clean message: "Insufficient Stocks! Requested: 5.000, Available: 2.000."
			DECLARE @CustomError NVARCHAR(4000) = 'Insufficient Stocks for ' + ISNULL(@productname, @parmprodcode) + '! You requested ' + CAST(CAST(@parmqty AS INT) AS VARCHAR) + ', but only ' + CAST(CAST(@invqty AS INT) AS VARCHAR) + ' are available.';

			-- Severity 16 forces SQL to jump instantly to the BEGIN CATCH block below
			RAISERROR(@CustomError, 16, 1);
		END
		-- =========================================================================
		-- 3. Pricing Logic
		--IF @parmbranchcode = @parmorigin
		--BEGIN
		--	SELECT @custkey = Customer FROM PurchaseOrderSummary WHERE PONumber = @parmpono;

		--	SELECT @specialpriceamount = SpecialPriceAmount FROM CustomerProductSetting
		--	WHERE ProductCode = @parmprodcode AND CustomerKey = @custkey;

		--	IF (@specialpriceamount = 0 OR @specialpriceamount IS NULL)
		--	BEGIN
		--		SELECT @specialpriceamount = SellingPrice FROM Products
		--		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;
		--	END
		--END
		SELECT @specialpriceamount = SellingPrice FROM Products
		WHERE ProductCode = @parmprodcode AND BranchCode = @parmorigin;
		-- 4. FIFO Processing & Delivery Details select * FROM InventorySettings
		SELECT @parminvsettings = isFIFO FROM InventorySettings;

		IF @parminvsettings = 1
		BEGIN
			SELECT @devseqno = ISNULL(MAX(SeqNo),0) + 1 FROM DeliveryDetails
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

			-- Execute FIFO Mapping
			EXEC sp_FiFoMappingHRI_JFC @parmeffectivitydate, @parmorigin, @parmbranchcode, @parmprodcode, @parmshipmentno, @parmqty,@specialpriceamount, @parmdevno, @parmpono, @parmdevseqno=@devseqno;

			-- Check if FIFO actually generated records (Meaning there was inventory available to deduct)
			IF EXISTS (SELECT TOP 1 DeliveryNo FROM InventoryDeliveryFIFO WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND ProductNo = @parmprodcode)
			BEGIN
				--IF NOT EXISTS (SELECT TOP 1 DeliveryNo FROM DeliveryDetails WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono AND ProductNo = @parmprodcode)
				--BEGIN
					INSERT INTO [dbo].[DeliveryDetails] (
						[SeqNo], [DeliveryNo], [PONumber], [ReferenceNumber], [ProductNo], [BarcodeNo],
						[ProductName], [QtyDelivered], [ActualQty], [Variance], [Cost], [SellingPrice],
						[Status], [isVat], [ProcessedBy], [isSettled], [isCreditMemo], [isReturned]
					)
					SELECT
						@devseqno, @parmdevno, @parmpono, @parmrefno, @parmprodcode, @parmbarcode,
						@productname, @parmqty, @parmqty, 0, 0, ISNULL(@specialpriceamount,0),
						'PENDING', @isvatablenew, @preparedby, 0, 0, 0;
				--END
			END
			ELSE
			BEGIN
				-- If you want it to insert into DeliveryDetails even if FIFO fails (e.g. out of stock),
				-- you need to add logic here! Currently, if out of stock, it skips inserting the detail.
				PRINT 'No Inventory Available for FIFO deduction. Detail skipped.';
			END
		END

		-- 5. Delivery Summary Logic (FIXED: Changed IF EXISTS to IF NOT EXISTS)
		IF NOT EXISTS (SELECT TOP(1) PONumber FROM DeliverySummary WHERE PONumber = @parmpono AND DeliveryNo = @parmdevno)
		BEGIN
			DECLARE @totalitem int, @totalqtydelivered decimal(18,3);

			SELECT @totalitem = ISNULL(COUNT(*),0), @totalqtydelivered = ISNULL(SUM(QtyDelivered),0)
			FROM DeliveryDetails
			WHERE DeliveryNo = @parmdevno AND PONumber = @parmpono;

			INSERT INTO [dbo].[DeliverySummary] (
				[DeliveryNo], [PONumber], [ReferenceNumber], [InvoiceNo], [BranchCode],
				[TotalItem], [TotalQtyDelivered], [TotalActualQty], [TotalVarianceVat], [TotalVarianceVatExempt],
				[EffectivityDate], [Status], [DateAdded], [PreparedBy], [isSettled], [isInvoiceUpdate]
			)
			SELECT
				@parmdevno, @parmpono, @parmrefno, @parmrefno, @parmbranchcode,
				@totalitem, @totalqtydelivered, 0, 0, 0,
				@parmeffectivitydate, 'PENDING', GETDATE(), @preparedby, 0, 0;
		END

		COMMIT TRAN;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN;

		-- Force the error to show up in SSMS or your App instead of failing silently
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END
GO

PRINT 'DEPLOYMENT COMPLETE: all 7 procedures renamed to _OLD and recreated with the fix.';
