# PROFOOD GMBH loan (EUR): monthly revaluation (and later payments) — plan (2026-10-12, revised)

Status: **proposal, nothing built.** Supersedes the "load as ExpenseSummary payable rows" idea of work-log Feature 23.
Revised the same day after the user's Peachtree screenshots (D:\SQLREF\viber1.png / viber2.jpg / viber3.jpg).

## 1. What the loan is (from the user's schedule and Peachtree)

- Lender PROFOOD GMBH. **Currency EUR** (the first draft wrongly said USD). Principal **EUR 800,000**, unchanged March–September 2026
  (no principal payments in the schedule).
- Booked in GL **20203 ADVANCES FROM MOTHER COMPANY** (Peachtree 2100), branch 888. Peachtree also carries it as AP invoice
  **LOAN051618** of vendor IMP-PRFO-0001.
- **Revalued every month end** at that day's PHP/EUR rate; the peso balance = EUR 800,000 × rate:

| Month end | Rate | Peso balance | Revaluation (Peachtree) |
|---|---|---|---|
| 03-31 | 69.6938 | 55,755,040.00 | +1,311,760.00 |
| 04-30 | 71.9955 | 57,596,400.00 | +1,841,360.00 |
| 05-31 | 71.6343 | 57,307,440.00 | −288,960.00 |
| 06-30 | 69.7746 | 55,819,680.00 | −1,487,760.00 |
| 07-31 | 70.5095 | **56,407,600.00** | +587,920.00 |
| 08-31 | 71.9305 | 57,544,400.00 | +1,136,800.00 (loss: CR 2100) |
| 09-30 | 70.2158 | 56,172,640.00 | −1,371,760.00 (gain: DR 2100) |

- How Peachtree booked it: in the cash disbursements journal against invoice LOAN051618 — a "payment" whose **cash account is
  6041 FRZ-Realized gain/loss-Forex** (gain month: DR 2100 / CR 6041; loss month: CR 2100). Description style:
  "FOREX REVALUATION 09.30.26 (E800000 @1.7147)".

## 2. What our system has (STAGING = production copy of 10-08)

- 20203 = **56,407,600.00**, only the 07-31 opening ticket 1 → equals Peachtree's 07-31 balance (EUR 800,000 × 70.5095).
- **The 08-31 and 09-30 revaluations are not booked** (20203 should be 56,172,640.00 at 09-30). Check production before posting.
- Forex account: **60323 REALIZED GAIN/LOSS ON FOREX** (= Peachtree 6041). No unrealized account.
- Branch allocation exists: Manual JV ticket 15949 (2026-09-25, "TO TAKE UP ALLOCATION OF LOAN FOREX REVALUATION GAIN(LOSS) TO
  BRANCHES") moved 833,362.65 of 60323 from 888 to 12 branches. Basis unknown.

## 3. Recommendation

### 3.1 Not through VoucheringManualFrm
The "Advances" radio idea copies Peachtree's habit of revaluing through a payment screen. Here: there is no loan invoice in AP (the loan
is only a GL balance); a loss month increases the debt (not a payment); a voucher would create a voucher no., CV no. and send its
"bank" leg (60323) to the bank reconciliation. A revaluation is a journal entry.

### 3.2 A small Loan Revaluation screen (Accounting)
- Data: `LoanAccount` (LoanID, lender 000125, Currency EUR, LiabilityAccount 20203, Branch 888, principal) and `LoanTransaction`
  (date, type OPENING / REVALUATION / PAYMENT / INTEREST, foreign amount, rate, PHP amount, ticket, reversed flag). Opening row
  2026-07-31: EUR 800,000 @ 70.5095 = 56,407,600.00 (ties to GL 20203; no posting).
- The screen shows the loan (EUR balance, last rate, PHP carrying = GL 20203); the user enters the month-end rate; the system posts
  EUR balance × (new rate − last rate) — DR 20203 / CR forex gain, or DR forex loss / CR 20203 — dated the month end, branch 888,
  accounts from JournalEntryMapping (e.g. `LOAN-REVAL`, default 60323 per Peachtree practice), description in the Peachtree style.
- One revaluation per loan per month; refused in a closed month (GLPeriodLock); reversible (reversal dated like the original).
- Optional, once the basis is known: the branch allocation of the gain/loss in the same posting (cross-branch, like ticket 15949).

### 3.3 Payments (later, only if needed)
A "Loan" mode in VoucheringManualFrm listing the loan's foreign balance and carrying rate; the user enters the EUR paid and the pesos
paid; DR 20203 = EUR paid × carrying rate, CR bank = pesos paid, the difference to the forex account; interest to 60313. Optional TVP
on sp_PostVoucherManual (backward compatible). Not needed for anything in the screenshots.

### 3.4 Interim (now, no development)
Manual JVs on 888 for the two missing months:
- 2026-08-31: DR 60323 1,136,800.00 / CR 20203 — "FOREX REVALUATION 08.31.26 (E800000 @1.421)"
- 2026-09-30: DR 20203 1,371,760.00 / CR 60323 — "FOREX REVALUATION 09.30.26 (E800000 @1.7147)"
→ 20203 = 56,172,640.00 = Peachtree. (Check production first; STAGING is a 10-08 copy.)

## 4. Questions for the accountant

1. Keep revaluation in 60323 (as Peachtree did with its realized account 6041), or a separate unrealized forex account?
2. Branch allocation: every month? On what basis (ticket 15949 split 833,362.65 over 12 branches)? Should the screen do it?
3. Any principal or interest payments planned? Withholding tax on interest?

**Answers (user, 2026-10-13):**
1. Only two accounts: 60323 realized forex gain/loss and 20203 advances from mother company. No unrealized account.
   Rate up (liability increases) = DR 60323 / CR 20203; rate down = DR 20203 / CR 60323. This is what script 65 posts.
2. Branch 888 only; no allocation to the branches. Script 65 posts on the loan's branch (888) only, so nothing to add.
3. Principal, interest and withholding: set aside for now (no payment mode built).

## 5. Build order (once answered)
1. Mapping row(s), tables, opening row (ties to GL 20203).
2. Revaluation screen + proc + reversal (+ allocation if wanted); rolled-back tests on DEV; reviews.
3. Exception Center check: register PHP carrying = GL 20203; one revaluation per month.
4. Payment mode only if needed. Scripts numbered `[NN]-…`; DEV → STAGING → production by the user.
