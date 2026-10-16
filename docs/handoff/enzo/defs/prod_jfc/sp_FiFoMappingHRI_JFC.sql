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
