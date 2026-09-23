-- 2026-09-23: JournalEntryMapping -- OR-OFFSET's bank-debit leg used the
-- wrong AmountType, so a plain Offset-only payment (no EWT/Discount) could
-- never balance and would always fail.
--
-- FOUND WHILE TESTING the customer-overpayment-credit feature (this is the
-- first time this exact code path was ever meaningfully exercised, since
-- Offset previously drew from an unrelated/never-funded account -- see
-- SQL/2026-09-23_CustomerOverpaymentCredit.sql). Confirmed pre-existing
-- and unrelated to today's account/mapping retarget: OR-OFFSET's Seq=1
-- {BANK} leg used AmountType='NET' (= Gross - EWT - Discount + Services,
-- i.e. does NOT subtract Offset at all), while every sibling EWT/Discount-
-- combined offset mnemonic correctly uses 'NET_OFFSET' (= Gross - EWT -
-- Discount - Offset + Services):
--     OR-DISC-OFFSET      Seq 1  {BANK}  NET_OFFSET   (correct)
--     OR-EWT-DISC-OFFSET  Seq 1  {BANK}  NET_OFFSET   (correct)
--     OR-EWT-OFFSET       Seq 1  {BANK}  NET_OFFSET   (correct)
--     OR-OFFSET           Seq 1  {BANK}  NET          (BUG -- only this one)
--
-- Reproduced live (test data inserted and rolled back, no permanent change):
-- Gross=2000.00, Offset=500.00 -> Debit side computed 2500.00 (2000 bank +
-- 500 to 20115) vs Credit side 2000.00 -- sp_AddPaymentClient's Step 5
-- balance check correctly caught the mismatch and threw 91002 rather than
-- posting an unbalanced entry, so no bad data was ever written; this was a
-- "feature never worked" bug, not a live corruption.
--
-- FIX: single-row UPDATE, scoped to the exact row confirmed above.
--
-- Deploy to CORECSERP_002_DEV first; mirror to CORECSJFC2026_STAGING only
-- after confirming with the user, per project convention.

UPDATE dbo.JournalEntryMapping
SET AmountType = 'NET_OFFSET'
WHERE Origin = 'OR'
  AND Mnemonic = 'OR-OFFSET'
  AND Seq = 1
  AND DebitCredit = 'D'
  AND AccountCode = '{BANK}'
  AND AmountType = 'NET';

-- sp-reviewer finding: a comment alone doesn't protect a future run of
-- this script against different seed data (e.g. if ever run on
-- CORECSJFC2026_STAGING and its row already differs) -- assert the
-- POST-condition rather than @@ROWCOUNT from the UPDATE itself, since the
-- UPDATE's own WHERE (AmountType='NET') makes a second run correctly match
-- 0 rows once already fixed -- a bare @@ROWCOUNT<>1 check would wrongly
-- fail on that safe idempotent re-run.
IF NOT EXISTS (
    SELECT 1 FROM dbo.JournalEntryMapping
    WHERE Origin = 'OR' AND Mnemonic = 'OR-OFFSET' AND Seq = 1
      AND DebitCredit = 'D' AND AccountCode = '{BANK}' AND AmountType = 'NET_OFFSET'
)
    THROW 50000, 'OR-OFFSET Seq=1 bank leg is not NET_OFFSET after this script -- the row may not exist or may have been altered unexpectedly. Investigate before proceeding.', 1;
