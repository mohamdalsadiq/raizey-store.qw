# P2-OBS-001 — Observability baseline (2026-10-08)

## Sentry decision: DEFERRED (needs Mohamed)
- Production loads `js.sentry-cdn.com` (a Sentry project exists somewhere) but we have
  no account access or DSN.
- **Decision:** Do not wire Sentry until Mohamed provides the project DSN.
  Until then, rely on Vercel logs + Supabase logs + audit_logs.
- PII rule: never log receipt images, full account numbers, or OTP codes.

## ID tracing: DONE
- `process-receipt` responses include `scanId` + `receiptHash` on every path
  (accept / reject / technical review).
- `claim_payment_receipt` returns the receipt `id`.
- `admin_confirm_topup` / wallet functions write `wallet_transactions.reference_id`.
- All financial mutations write `audit_logs` rows.

## Monitoring plan
1. **Financial anomalies:** review `wallet_transactions` daily for unexpected credits.
2. **Auth anomalies:** `audit_logs` with `source='customer_report'` via `report_fraud_alert`.
3. **Edge errors:** Supabase Functions logs for `process-receipt` (rate_limited, ocr failures).
4. **Deploy health:** Vercel deployment status after each merge.
