-- =============================================
-- Author: Eulz Avancena; 2026-09-07
-- Description: New Conversion master-detail report (Reporting/ConversionReportMasterDetail.cs),
--   built against the newer barcode-based Conversion system (ConversionBarcodeSummary /
--   ConversionBarcodeOutputDetails / ConversionBarcodeSourceDetails) rather than the older
--   ConversionSummary/ConversionDetails/ConversionFIFO tables the existing
--   Reporting/ConversionReports.cs uses -- the new system has 56 rows through 2026-09-02,
--   the old one only 8 rows through 2026-08-24 and is clearly superseded.
--
--   Three parameterized SPs, all filtered on @Branch/@Status/@DateFrom/@DateTo:
--     - sp_rpt_ConversionReport_Master  -- one row per conversion (the "mother" row),
--       joined to Branches for a readable BranchName.
--     - sp_rpt_ConversionReport_Source  -- ConversionBarcodeSourceDetails rows, i.e. the
--       actual per-lot INVENTORY DEDUCTION during conversion (InventorySeqNo, Barcode,
--       ProductCode, Qty, Cost, Amount) -- this is the "deduction of inventory" detail.
--     - sp_rpt_ConversionReport_Output  -- ConversionBarcodeOutputDetails rows, the
--       resulting output lots produced by the conversion.
--   Both detail SPs are scoped back to the same filtered master set via EXISTS, matching
--   the exact convention Reporting/ConversionReports.cs's own display() method already
--   uses for its master/detail/subdetail queries.
-- =============================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-------------------------------------------------------------------
-- 1. sp_rpt_ConversionReport_Master
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ConversionReport_Master', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_ConversionReport_Master;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_ConversionReport_Master
    @Branch   VARCHAR(5)  = NULL,
    @Status   VARCHAR(20) = NULL,
    @DateFrom DATE        = NULL,
    @DateTo   DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        S.ConversionRefNo,
        S.BranchCode,
        B.BranchName,
        S.ConversionType,
        S.TotalSourceQty,
        S.TotalSourceCost,
        S.CuttingCharge,
        S.TotalDriplossQty,
        S.CostBasisQty,
        S.MaterialRatePerUnit,
        S.ChargeRatePerLine,
        S.Status,
        S.DateConverted,
        S.ConvertedBy,
        S.ReversedBy,
        S.DateReversed,
        S.FinalizedBy,
        S.DateFinalized,
        S.Remarks
    FROM dbo.ConversionBarcodeSummary S
    LEFT JOIN dbo.Branches B ON B.BranchCode = S.BranchCode
    WHERE (@Branch IS NULL OR S.BranchCode = @Branch)
      AND (@Status IS NULL OR S.Status = @Status)
      AND (@DateFrom IS NULL OR CAST(S.DateConverted AS DATE) >= @DateFrom)
      AND (@DateTo IS NULL OR CAST(S.DateConverted AS DATE) <= @DateTo)
    ORDER BY S.DateConverted DESC;
END
GO

-------------------------------------------------------------------
-- 2. sp_rpt_ConversionReport_Source -- inventory deduction detail.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ConversionReport_Source', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_ConversionReport_Source;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_ConversionReport_Source
    @Branch   VARCHAR(5)  = NULL,
    @Status   VARCHAR(20) = NULL,
    @DateFrom DATE        = NULL,
    @DateTo   DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        D.ConversionRefNo,
        D.SeqNo,
        D.InventorySeqNo,
        D.Barcode,
        D.ProductCode,
        D.Description,
        D.Qty,
        D.Cost,
        D.Amount
    FROM dbo.ConversionBarcodeSourceDetails D
    WHERE EXISTS (
        SELECT 1 FROM dbo.ConversionBarcodeSummary S
        WHERE S.ConversionRefNo = D.ConversionRefNo
          AND (@Branch IS NULL OR S.BranchCode = @Branch)
          AND (@Status IS NULL OR S.Status = @Status)
          AND (@DateFrom IS NULL OR S.DateConverted >= @DateFrom)
          AND (@DateTo IS NULL OR S.DateConverted < DATEADD(DAY, 1, @DateTo))
    )
    ORDER BY D.ConversionRefNo, D.SeqNo;
END
GO

-------------------------------------------------------------------
-- 3. sp_rpt_ConversionReport_Output -- resulting output lots.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.sp_rpt_ConversionReport_Output', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rpt_ConversionReport_Output;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.sp_rpt_ConversionReport_Output
    @Branch   VARCHAR(5)  = NULL,
    @Status   VARCHAR(20) = NULL,
    @DateFrom DATE        = NULL,
    @DateTo   DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        D.ConversionRefNo,
        D.SeqNo,
        D.ProductCode,
        D.Description,
        D.Qty,
        D.IsDriploss,
        D.UnitCost,
        D.TotalCost,
        D.NewInventorySeqNo,
        D.NewBarcode,
        -- FinalCost was added 2026-09-02 (the Finalize/GL feature) with no backfill, so
        -- output rows from conversions posted before that date have FinalCost=NULL forever
        -- -- summed unwrapped, they'd silently drop out of the footer total for any date
        -- range spanning pre-09-02 conversions while Qty/UnitCost/TotalCost stayed included.
        -- Falls back to the system-computed UnitCost for those rows.
        COALESCE(D.FinalCost, D.UnitCost) AS FinalCost
    FROM dbo.ConversionBarcodeOutputDetails D
    WHERE EXISTS (
        SELECT 1 FROM dbo.ConversionBarcodeSummary S
        WHERE S.ConversionRefNo = D.ConversionRefNo
          AND (@Branch IS NULL OR S.BranchCode = @Branch)
          AND (@Status IS NULL OR S.Status = @Status)
          AND (@DateFrom IS NULL OR S.DateConverted >= @DateFrom)
          AND (@DateTo IS NULL OR S.DateConverted < DATEADD(DAY, 1, @DateTo))
    )
    ORDER BY D.ConversionRefNo, D.SeqNo;
END
GO

PRINT 'DEPLOYMENT COMPLETE: sp_rpt_ConversionReport_Master, sp_rpt_ConversionReport_Source, sp_rpt_ConversionReport_Output.';
