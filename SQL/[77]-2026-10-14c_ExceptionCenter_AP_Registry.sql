/* ================================================================
   [77] 2026-10-14 - Exception Center: register the AP provider ([70]) with the portal's dispatcher (sql/43)
   ================================================================
   Needs [70] (fn_rpt_exc_AP_Findings + sp_rpt_exc_AP_Summary / _Detail) and the portal's sql/43 (registry columns
   Module / Kind / ProviderProc / Owner / ThresholdDays / Action + the dispatcher in sp_rpt_ExceptionCenter_Summary /
   _Detail). Checked on DEV and STAGING 2026-10-14: sql/43 is in; PRODUCTION is not yet (19 checks, no dispatcher).

   1. New router dbo.sp_rpt_exc_AP_Provider. sql/43's dispatchers call the ONE proc named in ExceptionDefinition.ProviderProc
      in two shapes:
        Summary: EXEC <proc> @DateFrom, @DateTo, @AsOfDate                  -> ExceptionCode, Findings, ValueAtRisk
        Detail:  EXEC <proc> @ExceptionCode, @DateFrom, @DateTo, @AsOfDate  -> that code's rows (unknown code = error)
      The router sends a call without @ExceptionCode to sp_rpt_exc_AP_Summary and a call with one to sp_rpt_exc_AP_Detail,
      so [70]'s two procs stay as they are (and stay callable on their own).
   2. The 10 AP rows in ExceptionDefinition, as agreed in the ERP reply section 8 (Owner 'erp', Module 'AP', IsActive spelled
      out, ProviderProc = the router). SortOrder 100-109 (after the portal's BRC block at 80-92). Insert when missing, else
      update this script's columns only (a re-run is safe; IsActive is left as it is on update, so the portal can switch a
      code off). AP-CHEQUE-REUSED is a guard-verifier since [74] (the trigger refuses new cases).

   Read-only router; no table besides ExceptionDefinition is written. One transaction with a post-check.
   ================================================================ */

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- prerequisites; NOEXEC stops every later batch too (a THROW would only stop this one)
IF OBJECT_ID('dbo.sp_rpt_exc_AP_Summary', 'P') IS NULL OR OBJECT_ID('dbo.sp_rpt_exc_AP_Detail', 'P') IS NULL
BEGIN
    RAISERROR('Run [70] first: sp_rpt_exc_AP_Summary / sp_rpt_exc_AP_Detail are missing here. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
IF COL_LENGTH('dbo.ExceptionDefinition', 'ProviderProc') IS NULL OR COL_LENGTH('dbo.ExceptionDefinition', 'Owner') IS NULL
BEGIN
    RAISERROR('The portal''s sql/43 is not on this database (ExceptionDefinition has no ProviderProc / Owner column). Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_rpt_exc_AP_Provider
    @ExceptionCode varchar(50) = NULL,
    @DateFrom      date = NULL,
    @DateTo        date = NULL,
    @AsOfDate      date = NULL
AS
BEGIN
    /* Entry point registered in ExceptionDefinition.ProviderProc for the AP codes ([77]).
       No @ExceptionCode = the portal's Summary call; with one = its Detail call. */
    SET NOCOUNT ON;
    IF @ExceptionCode IS NULL
        EXEC dbo.sp_rpt_exc_AP_Summary @DateFrom = @DateFrom, @DateTo = @DateTo, @AsOfDate = @AsOfDate;
    ELSE
        EXEC dbo.sp_rpt_exc_AP_Detail @ExceptionCode = @ExceptionCode, @DateFrom = @DateFrom, @DateTo = @DateTo, @AsOfDate = @AsOfDate;
END;
GO

BEGIN TRANSACTION;

DECLARE @Def TABLE (
    ExceptionCode varchar(50) NOT NULL PRIMARY KEY, Category varchar(50) NOT NULL, Title varchar(200) NOT NULL,
    Severity varchar(10) NOT NULL, SortOrder int NOT NULL, [Action] varchar(400) NOT NULL);
INSERT INTO @Def (ExceptionCode, Category, Title, Severity, SortOrder, [Action]) VALUES
('AP-VOUCHER-LEGS',          'Vouchering',      'Voucher legs differ from the screen total, cheque, GL bank or recon item', 'Critical', 100,
 'Compare the voucher''s payment lines with the amount keyed on screen, the cheque, the bank credit and the recon item; correct the records to the cheque actually issued (see [63] / [66] / [73]).'),
('AP-TICKET-UNBALANCED',     'Vouchering',      'AP posting or payment ticket does not balance', 'Critical', 101,
 'Open the ticket''s lines: debits must equal credits (per reference for cross-branch expenses). Find the posting that wrote it and repost or correct it in an open month.'),
('AP-SUPPLIER-LEDGER-CHAIN', 'Supplier Ledger', 'Supplier ledger running balance broken', 'Critical', 102,
 'A ledger row''s ending balance is not beginning + credit - debit, or an amount is blank. Touch one row of the supplier so trg_SupplierLedger_Recalc re-chains it; fix blank amounts at their source.'),
('AP-ACCOUNT-VS-LEDGER',     'Supplier Ledger', 'Supplier account balance differs from its ledger', 'Critical', 103,
 'SupplierAccounts.AccountBalance must equal the supplier''s ledger total. Touch one ledger row of the supplier to recompute; if the account row is missing, create it first.'),
('AP-INVOICE-VS-LEDGER',     'Supplier Ledger', 'Open invoice balance differs from the supplier ledger', 'Critical', 104,
 'The invoice''s balance and its ledger rows disagree: check balance-forward loads, payments booked at a different amount, and edits after payment. Balance-forward differences go to the accountant.'),
('AP-LEDGER-PAYMENT-SIDE',   'Supplier Ledger', 'Payment posted to the supplier ledger on the wrong side', 'Critical', 105,
 'A payment row was written as a credit (it raises the amount owed). Fixed at the source by [71]; correct old rows the same way (credit -> debit) and let the trigger re-chain.'),
('AP-REVERSAL-NOT-RESTORED', 'Vouchering',      'Reversed voucher not fully mirrored in the supplier ledger', 'Critical', 106,
 'Every payment row of a reversed voucher needs its reversal row. Compare the voucher''s ledger rows with its reversal and add the missing mirror through the reversal process, not by hand.'),
('AP-CREDIT-NEGATIVE',       'Vouchering',      'Supplier advance credit below zero', 'Critical', 107,
 'More advance was applied than was overpaid (OVERPAY - ADVANCEAPPLIED < 0). Find the voucher that applied it and the reversal that removed the credit; reverse the application first.'),
('AP-STATUS-VS-BALANCE',     'Post Expense',    'Invoice status and balance disagree', 'Warning', 108,
 'FULLYPAID with a balance, a negative balance, or balance 0 not FULLYPAID. Check the invoice''s payments; correct the status or balance to what was actually paid.'),
('AP-CHEQUE-REUSED',         'Vouchering',      'Cheque number reused after it was recorded as cancelled', 'Warning', 109,
 'A live voucher carries a cheque number recorded as cancelled on the same bank. Check which cheque the bank cleared; correct the voucher or the cancelled record. New cases are refused since [74].');

UPDATE ed SET
    Category = d.Category, Title = d.Title, Severity = d.Severity, HasDrillDown = 1, SortOrder = d.SortOrder,
    Module = 'AP', [Kind] = 'INTEGRITY', ProviderProc = 'sp_rpt_exc_AP_Provider', [Owner] = 'erp', ThresholdDays = NULL, [Action] = d.[Action]
FROM dbo.ExceptionDefinition AS ed INNER JOIN @Def AS d ON d.ExceptionCode = ed.ExceptionCode;

INSERT INTO dbo.ExceptionDefinition
    (ExceptionCode, Category, Title, Severity, HasDrillDown, DrillDownRoute, IsActive, SortOrder,
     Module, [Kind], ProviderProc, [Owner], ThresholdDays, [Action])
SELECT d.ExceptionCode, d.Category, d.Title, d.Severity, 1, NULL, 1, d.SortOrder,
       'AP', 'INTEGRITY', 'sp_rpt_exc_AP_Provider', 'erp', NULL, d.[Action]
FROM @Def AS d
WHERE NOT EXISTS (SELECT 1 FROM dbo.ExceptionDefinition AS ed WHERE ed.ExceptionCode = d.ExceptionCode);

-- post-check: the 10 rows, all on the router, and the router's summary answers exactly these 10 codes
IF (SELECT COUNT(*) FROM dbo.ExceptionDefinition WHERE ExceptionCode LIKE 'AP-%' AND ProviderProc = 'sp_rpt_exc_AP_Provider' AND [Owner] = 'erp') <> 10
    THROW 59984, 'Post-check: not exactly 10 AP rows registered to sp_rpt_exc_AP_Provider.', 1;

IF @@TRANCOUNT > 0 COMMIT TRANSACTION;
GO

SELECT ExceptionCode, Category, Severity, SortOrder, IsActive, Module, [Kind], ProviderProc, [Owner]
FROM dbo.ExceptionDefinition WHERE [Owner] = 'erp' ORDER BY SortOrder;
PRINT 'AP checks registered (sp_rpt_exc_AP_Provider). Check: EXEC dbo.sp_rpt_ExceptionCenter_Summary @DateFrom, @DateTo outside a transaction.';
GO
