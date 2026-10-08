# P2-DB-002 — bank_key exposure decision (2026-10-08)

## Decision: NOT SENSITIVE — documented, no change

- `payment_methods.bank_key` holds values like `"bankak"` or `""`.
- Purpose: matches the receipt's detected provider (`provider.key`) against the
  payment method in `receipt-judge-core.ts:925`:
  `if (bankKey && provider && provider.key !== bankKey) → 'bank_provider_mismatch'`
- It is a **provider slug**, not a secret. Anon readability is intentional —
  the storefront needs it to display/route payment methods.
- No PII, no credential, no internal identifier.

## Status: CLOSED (documented)
