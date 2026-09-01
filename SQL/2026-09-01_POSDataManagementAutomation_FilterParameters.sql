-- =============================================
-- Author: Eulz Avancena (original); modified 2026-09-01
-- Description: sp_GetSalesDateForDataProcessing had NO parameters at all --
--              it even had a commented-out hardcoded test filter left in it
--              ("--AND a.BranchCode='035' and a.DateExecute between ... and
--              a.MachineUsed='POS1'") that was never converted into real
--              parameters. Because of this, POSDataManagementAutomation.cs's
--              btnStart -> timer1_Tick -> RunProcessingCycleAsync ->
--              GetPendingBatchesAsync chain always pulled EVERY unprocessed
--              batch system-wide and processed all of them, completely
--              ignoring the Branch / Sales From / Sales To / Machine filter
--              fields on the form -- only PrintZRead (the Z-read print
--              worker) actually read those fields. This adds the missing
--              filter parameters, all optional (NULL = no filter on that
--              dimension) so any other future caller isn't forced to supply
--              all four.
-- =============================================

IF OBJECT_ID('dbo.sp_GetSalesDateForDataProcessing', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetSalesDateForDataProcessing', 'sp_GetSalesDateForDataProcessing_OLD_09012026190000';
GO

CREATE PROCEDURE [dbo].[sp_GetSalesDateForDataProcessing]
    @BranchCode  CHAR(3)     = NULL,
    @FromDate    DATE        = NULL,
    @ToDate      DATE        = NULL,
    @MachineUsed VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        a.BranchCode, a.DateExecute, a.MachineUsed, a.TotalNetSales, a.VatExemptSale
    FROM dbo.POSZReadingTransactions a WITH (NOLOCK)
    WHERE NOT EXISTS (
                SELECT 1 FROM dbo.SalesManagement b
                WHERE a.BranchCode = b.BranchCode
                  AND a.DateExecute = b.SalesDate
                  AND a.MachineUsed = b.MachineName
          )
      AND (@BranchCode  IS NULL OR a.BranchCode  = @BranchCode)
      AND (@FromDate    IS NULL OR a.DateExecute >= @FromDate)
      AND (@ToDate      IS NULL OR a.DateExecute <= @ToDate)
      AND (@MachineUsed IS NULL OR a.MachineUsed = @MachineUsed)
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_GetSalesDateForDataProcessing now accepts @BranchCode/@FromDate/@ToDate/@MachineUsed filters.';
