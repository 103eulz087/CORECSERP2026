/* ================================================================
   2026-10-05b (DEV only): harden dbo.fn_InvIsStickerBarcode
   ================================================================
   DEV got script 2026-10-05_InvFIFO_StickerRule.sql before the sp-reviewer's
   hardening (strip CR / LF / TAB / NBSP; case-insensitive 'A01'). That script
   now carries the hardened function, so STAGING needs only it. This brings
   DEV's copy to the same text. Backup: fn_InvIsStickerBarcode_OLD_10052026190000.
   ================================================================ */
SET XACT_ABORT ON;
BEGIN TRANSACTION;
EXEC sp_rename 'dbo.fn_InvIsStickerBarcode', 'fn_InvIsStickerBarcode_OLD_10052026190000';
GO
CREATE FUNCTION dbo.fn_InvIsStickerBarcode (@Barcode VARCHAR(120))
RETURNS TABLE
AS
/*
    IsSticker = 1 when the lot carries a physical barcode sticker that is
    scanned (FIFO Auto / By Shipment never takes part of it):
      'A01...'        received from the supplier
      19 characters   received in the offline app
    Everything else (blank, B01 / C01 / D01 tags) is not a sticker.
    The ONE definition of the rule (2026-10-05); change it here only.
    CR / LF / TAB / non-breaking space are stripped first: a scanned or
    imported 19-digit code with a stray trailing character must still count
    as a sticker. 'A01' is compared case-insensitively whatever the collation.
*/
RETURN
    SELECT CAST(CASE WHEN x.b LIKE 'A01%' COLLATE SQL_Latin1_General_CP1_CI_AS OR LEN(x.b) = 19 THEN 1 ELSE 0 END AS BIT) AS IsSticker
    FROM (SELECT LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@Barcode, ''),
                 CHAR(13), ''), CHAR(10), ''), CHAR(9), ''), CHAR(160), ''))) AS b) AS x;
GO
IF @@TRANCOUNT >= 1 AND OBJECT_ID('dbo.fn_InvIsStickerBarcode', 'IF') IS NOT NULL
   AND OBJECT_DEFINITION(OBJECT_ID('dbo.fn_InvIsStickerBarcode')) LIKE '%CHAR(160)%'
BEGIN COMMIT TRANSACTION; PRINT 'Applied.'; END
ELSE
BEGIN IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; RAISERROR('NOT APPLIED: rolled back.', 16, 1); END
GO
