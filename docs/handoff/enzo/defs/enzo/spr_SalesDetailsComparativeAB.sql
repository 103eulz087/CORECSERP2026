CREATE PROC [dbo].[spr_SalesDetailsComparativeAB] --exec [spr_SalesDetailsComparativeAB] '030','POS3','2026-08-01','2026-08-31'
	@parmbrcode char(3)
	,@parmmachinename varchar(30)
	,@datefrom date
	,@dateto date
AS
BEGIN


SELECT a.DateExecute,a.BranchCode,a.MachineUsed
			 ,a.BeginningSINo,a.EndingSINo
			 ,a.VatExemptSale,b.VatExemptSale as VatExemptSale2
			 ,(a.VatExemptSale-b.VatExemptSale) as VatExemptDiff
			 ,a.VatableSale,b.VatableSale as VatableSale2
			 ,(a.VatableSale-b.VatableSale) as VatableSaleDiff,
			 a.VatInput,b.VatInput as VatInput2
			 ,( a.VatInput- b.VatInput) as VatInputDiff
			 ,a.TotalNetSales,b.TotalNetSales as TotalNetSales2,(a.TotalNetSales-b.TotalNetSales) as TotalNetSalesDiff
			 ,a.ExecuteBy
			 FROM POSZReadingTransactions a with(nolock)
			 INNER JOIN POSZReadingTransactions2 b with(nolock) 
				ON a.BranchCode=b.BranchCode
				and a.BeginningSINo=b.BeginningSINo
				and a.EndingSINo=b.EndingSINo
				and a.MachineUsed=b.MachineUsed
			 WHERE a.BranchCode=@parmbrcode 
			 and a.DateExecute between @datefrom and @dateto
			 and a.MachineUsed = @parmmachinename
			 ORDER BY a.DateExecute ASC
END
 
