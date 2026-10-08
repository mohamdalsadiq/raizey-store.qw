# P2-SEC-002 — Rate-limit review (2026-10-08)

## Verdict: already hardened — no changes needed

The concerns in the original task description are **outdated**. Both edge functions
already enforce effective rate limits:

### process-receipt
- **Per-user** limit (not IP): 12 scans / 10 minutes (`RATE_WINDOW_MINUTES=10`, `MAX_SCANS_PER_WINDOW=12`)
- Enforced in `enforceRateLimit()` via `receipt_scan_results` count per `user_id`
- Authenticated only — 401 without valid JWT
- Returns 429 with `Retry-After: 600` on exceed

### chat-assistant
- Identity = `user:{id}` if authenticated, else `ip:{address}`
- Enforced via live `consume_chat_rate_limit(rate_key, limit, window)` RPC (verified live 2026-10-08)
- Limit: 12 requests / 10 minutes
- Returns 429 with `Retry-After` on exceed
- **Fails closed**: 503 `rate_limiter_unavailable` if the limiter errors (no bypass)

## Gaps considered
- Anonymous chat users are IP-limited — acceptable for a public storefront assistant;
  abuse would require IP rotation, and each request still costs a bounded Gemini call.
- No changes made; this task is closed as "verified already compliant".
