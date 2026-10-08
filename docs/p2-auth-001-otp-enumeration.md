# P2-AUTH-001 — OTP account-enumeration (2026-10-08)

## Finding: CONFIRMED in our UI (was NOT_CONFIRMED for Supabase API)
- Supabase's `signInWithOtp` API itself does not leak, but `login.html` did:
  - Existing email → "أرسلنا كودًا من 6 أرقام إلى ..."
  - Non-existing email → "لا يوجد حساب مسجل بهذا البريد" (+ register link)
- An attacker could enumerate registered emails.

## Fix (login.html)
- On `isNoAccountError`, show the SAME neutral message:
  "إذا كان هذا البريد مسجلاً لدينا، أرسلنا إليه كودًا من 6 أرقام."
- The OTP panel is shown in both cases; verification fails naturally for
  unregistered emails. No existence signal remains.

## Status: FIXED
