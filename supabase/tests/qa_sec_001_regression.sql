-- QA-SEC-001: Security regression test suite
-- Covers all P0/P1/P2 security invariants. Run after any security-related change.
-- Self-cleaning: runs in one transaction, rolls back test data.
-- Expected: ALL PASS

DO $$
DECLARE
  v_uid_a uuid := gen_random_uuid();
  v_uid_b uuid := gen_random_uuid();
  v_admin uuid;
  v_pass int := 0; v_fail int := 0;
  v_log text := '';
  v_scan uuid;
  v_r RECORD;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role = 'admin' LIMIT 1;
  PERFORM set_config('raizey.trusted_order', 'on', true);
  INSERT INTO auth.users (id, email) VALUES (v_uid_a, 'qasec_a@example.com'), (v_uid_b, 'qasec_b@example.com');

  -- S1: audit_logs append-only (P1-SEC-001) — no UPDATE/DELETE policy
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='audit_logs'
               AND (cmd='UPDATE' OR cmd='DELETE')) THEN
      v_fail := v_fail + 1; v_log := v_log || 'S1 FAIL update/delete policy exists;';
    ELSE v_pass := v_pass + 1; v_log := v_log || 'S1 PASS append-only;'; END IF;
  END;

  -- S2: settings allowlist (P1-DB-001) — anon sees only 3 keys
  BEGIN
    IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='settings'
        AND roles::text LIKE '%anon%') = 1 THEN
      v_pass := v_pass + 1; v_log := v_log || 'S2 PASS single anon policy;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S2 FAIL anon policies;'; END IF;
  END;

  -- S3: is_admin banned check (P1-AUTH-001)
  BEGIN
    IF (SELECT prosrc FROM pg_proc WHERE proname='is_admin' LIMIT 1) LIKE '%is_banned%' THEN
      v_pass := v_pass + 1; v_log := v_log || 'S3 PASS banned check;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S3 FAIL no banned check;'; END IF;
  END;

  -- S4: claim user binding (P1-RCP-001/002)
  INSERT INTO public.receipt_scan_results (user_id, receipt_hash, image_bytes, mime_type, expires_at, submission_allowed, amount_detected, tx_ref_ocr)
  VALUES (v_uid_a, repeat('f',64), 1234, 'image/png', now() + interval '1 hour', true, 1000, 'TX999991')
  RETURNING id INTO v_scan;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid_b)::text, true);
  BEGIN
    PERFORM public.claim_payment_receipt('topup','TX999991', repeat('f',64), NULL, NULL, NULL, 1000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan));
    v_fail := v_fail + 1; v_log := v_log || 'S4 FAIL cross-user;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%receipt_scan_not_found%' THEN v_pass := v_pass + 1; v_log := v_log || 'S4 PASS user binding;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S4 FAIL wrong err;'; END IF;
  END;

  -- S5: topup amount binding (P1-FIN-001) — function requires override on mismatch
  BEGIN
    IF (SELECT prosrc FROM pg_proc WHERE proname='admin_confirm_topup' LIMIT 1) LIKE '%override%' THEN
      v_pass := v_pass + 1; v_log := v_log || 'S5 PASS amount binding;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S5 FAIL no binding;'; END IF;
  END;

  -- S6: wallet ledger (P1-FIN-002) — all 7 functions write ledger
  BEGIN
    IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname IN
        ('admin_confirm_topup','create_wallet_order','create_wallet_orders_bulk',
         'process_referral_commission','redeem_gift_card','redeem_loyalty_points','admin_refund_wallet')
        AND p.prosrc LIKE '%wallet_transactions%') = 7 THEN
      v_pass := v_pass + 1; v_log := v_log || 'S6 PASS 7/7 ledger;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S6 FAIL ledger gap;'; END IF;
  END;

  -- S7: refund idempotency (P2-FIN-001)
  BEGIN
    IF (SELECT prosrc FROM pg_proc WHERE proname='admin_refund_wallet' LIMIT 1) LIKE '%already_refunded%' THEN
      v_pass := v_pass + 1; v_log := v_log || 'S7 PASS idempotent;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S7 FAIL no idempotency;'; END IF;
  END;

  -- S8: giftcard rate limit (P3-SEC-001)
  BEGIN
    IF (SELECT prosrc FROM pg_proc WHERE proname='redeem_gift_card' LIMIT 1) LIKE '%giftcard_rate_limited%' THEN
      v_pass := v_pass + 1; v_log := v_log || 'S8 PASS rate limit;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S8 FAIL no rate limit;'; END IF;
  END;

  -- S9: coupon atomic (P1-DB-002) — dead function gone
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='increment_coupon_usage') THEN
      v_pass := v_pass + 1; v_log := v_log || 'S9 PASS dead fn gone;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S9 FAIL dead fn exists;'; END IF;
  END;

  -- S10: fraud reports via trusted RPC only (P0-SEC-001)
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='audit_logs'
                   AND policyname LIKE '%customer%') THEN
      v_pass := v_pass + 1; v_log := v_log || 'S10 PASS no customer policy;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'S10 FAIL customer policy;'; END IF;
  END;

  RAISE EXCEPTION 'QASECRESULT % passed, % failed | %', v_pass, v_fail, v_log;
END $$;
