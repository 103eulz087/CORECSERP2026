-- 2026-09-23: Customer Overpayment Credit -- give OverPay a real GL home so
-- it can legitimately carry forward as an offset against a future invoice.
--
-- CONTEXT (ClientPaymentsDevExAcctg.cs / sp_AddPaymentClient): the "OverPay"
-- and "OffsetAmount" grid fields already exist and are functionally wired --
-- overpay an invoice today, type the excess into a later invoice's
-- OffsetAmount, and Balance/PayStatus already compute correctly (verified:
-- Gross = AmountPaid+Offset settles the full invoice, PayStatus->FULLYPAID).
--
-- The gap was purely in JournalEntryMapping: OVERPAY credited 404 (OTHER
-- INCOME -- permanent revenue recognition) while OFFSET debited 20202
-- (ADVANCES FROM ACCOUNT MANAGERS -- an unrelated related-party/internal
-- liability account, confirmed with the user it was never meant for this).
-- The two legs were never actually connected to the same account, so using
-- them together would have overstated Other Income and drawn down an
-- unrelated liability with no real balance behind it.
--
-- FIX:
--   1. New liability account 20115 (Current Liabilities, next open slot
--      after 20114) -- same shape as sibling accounts in that range (D/
--      postable, LevelNumber 2, SummaryAccount 201, Nature C).
--   2. Retarget OVERPAY's credit leg (404->20115) and OFFSET's debit leg
--      (20202->20115) so both mechanisms now move the same account --
--      OverPay creates the liability, Offset draws it down.
--   3. sp_GetCustomerAvailableCredit -- read-only, lets the UI show a
--      customer's running unapplied-overpayment balance before the next
--      payment, computed from ARPaymentDetails/PaymentHeader (no new
--      tracking table needed -- PaymentHeader.Status='REVERSED' already
--      correctly excludes reversed payments).
--
-- Scope-checked before changing JournalEntryMapping: grepped every row
-- using AccountCode 404 or 20202 (any Origin/Mnemonic) --
--   - 20202: exactly the 4 OFFSET-related rows (ConditionFlag='HasOffset'),
--     nothing else in the whole table references it. Safe to retarget all.
--   - 404: 4 OVERPAY rows (ConditionFlag='HasOverpay') plus one unrelated,
--     already-INACTIVE row (OR-COMPLETE, AmountType='NET', IsActive=0) --
--     the UPDATE below is scoped by ConditionFlag so that inactive row is
--     untouched.
--
-- Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
-- after confirming with the user, per project convention.

-- ----------------------------------------------------------------
-- 1. New GL account
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '20115')
BEGIN
    INSERT INTO dbo.ChartOfAccounts
        (AccountCode, Description, AccountType, LevelNumber, SummaryAccount,
         GLSL, BranchCode, YearEndIndicator, Nature, DueToFromIndicator)
    VALUES
        ('20115', 'CUSTOMER ADVANCES / OVERPAYMENTS', 'D', 2, '201',
         'S', '888', 'BS', 'C', NULL);
END
GO

-- ----------------------------------------------------------------
-- 2. Retarget OVERPAY (credit leg) and OFFSET (debit leg) to the new account
-- ----------------------------------------------------------------
UPDATE dbo.JournalEntryMapping
SET AccountCode = '20115'
WHERE Origin = 'OR'
  AND AccountCode = '404'
  AND AmountType = 'OVERPAY'
  AND ConditionFlag = 'HasOverpay';
-- Expected: 4 rows (OR-DISC-OVERPAY, OR-EWT-DISC-OVERPAY, OR-EWT-OVERPAY, OR-OVERPAY)

UPDATE dbo.JournalEntryMapping
SET AccountCode = '20115'
WHERE Origin = 'OR'
  AND AccountCode = '20202'
  AND ConditionFlag = 'HasOffset';
-- Expected: 4 rows (OR-DISC-OFFSET, OR-EWT-DISC-OFFSET, OR-EWT-OFFSET, OR-OFFSET)
GO

-- ----------------------------------------------------------------
-- 3. sp_GetCustomerAvailableCredit -- read-only, one row per call
-- ----------------------------------------------------------------
IF OBJECT_ID('dbo.sp_GetCustomerAvailableCredit', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_GetCustomerAvailableCredit', 'sp_GetCustomerAvailableCredit_OLD_09232026030000';
GO

CREATE PROCEDURE dbo.sp_GetCustomerAvailableCredit
(
    @CustomerKey CHAR(8)
)
AS
/*
    Running unapplied-overpayment balance for one customer:
        SUM(OVERPAY amounts) - SUM(OFFSET amounts already applied),
    across non-reversed PaymentHeader rows only. No dedicated tracking
    table -- ARPaymentDetails/PaymentHeader already carry everything
    needed, and PaymentHeader.Status='REVERSED' already correctly
    excludes a reversed payment's OVERPAY/OFFSET rows from the total.
    Always returns exactly one row (0.00 when the customer has never
    overpaid), even when no matching rows exist.
    Callers: ClientPaymentsDevExAcctg.cs (customer-select refresh).
*/
BEGIN
    SET NOCOUNT ON;

    SELECT
        ISNULL(SUM(CASE WHEN apd.PaymentType = 'OVERPAY' THEN apd.Amount ELSE 0 END), 0)
      - ISNULL(SUM(CASE WHEN apd.PaymentType = 'OFFSET'  THEN apd.Amount ELSE 0 END), 0)
        AS AvailableCredit
    FROM dbo.PaymentHeader ph
    JOIN dbo.ARPaymentDetails apd ON apd.PaymentHeaderID = ph.PaymentHeaderID
    WHERE ph.CustomerKey = @CustomerKey
      AND ph.Status <> 'REVERSED';
END
GO
