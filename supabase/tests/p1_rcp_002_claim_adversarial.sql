DO $$
DECLARE
  v_uid_a uuid := gen_random_uuid();
  v_uid_b uuid := gen_random_uuid();
  v_scan1 uuid; v_scan2 uuid; v_scan3 uuid; v_scan4 uuid;
  v_r RECORD;
  v_pass int := 0; v_fail int := 0;
  v_amt numeric;
  v_log text := '';
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid_a, 'advtest_a@example.com'), (v_uid_b, 'advtest_b@example.com');

  INSERT INTO public.receipt_scan_results (user_id, receipt_hash, image_bytes, mime_type, expires_at, submission_allowed, amount_detected, tx_ref_ocr)
  VALUES (v_uid_a, repeat('a',64), 1234, 'image/png', now() + interval '1 hour', true, 5000, 'TX111111')
  RETURNING id INTO v_scan1;
  INSERT INTO public.receipt_scan_results (user_id, receipt_hash, image_bytes, mime_type, expires_at, submission_allowed, amount_detected, tx_ref_ocr)
  VALUES (v_uid_a, repeat('b',64), 1234, 'image/png', now() + interval '1 hour', true, 3000, 'TX222222')
  RETURNING id INTO v_scan2;
  INSERT INTO public.receipt_scan_results (user_id, receipt_hash, image_bytes, mime_type, expires_at, submission_allowed, amount_detected, tx_ref_ocr)
  VALUES (v_uid_a, repeat('c',64), 1234, 'image/png', now() - interval '1 hour', true, 7000, 'TX333333')
  RETURNING id INTO v_scan3;
  INSERT INTO public.receipt_scan_results (user_id, receipt_hash, image_bytes, mime_type, expires_at, submission_allowed, amount_detected, tx_ref_ocr)
  VALUES (v_uid_a, repeat('d',64), 1234, 'image/png', now() + interval '1 hour', true, 4000, 'TX444444')
  RETURNING id INTO v_scan4;

  -- T1: valid claim by owner
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid_a)::text, true);
  BEGIN
    SELECT * INTO v_r FROM public.claim_payment_receipt('topup','TX111111', repeat('a',64), NULL, NULL, NULL, 5000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan1)) LIMIT 1;
    IF v_r.amount_verified THEN v_pass := v_pass + 1; v_log := v_log || 'T1 PASS valid claim;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T1 FAIL not verified;'; END IF;
  EXCEPTION WHEN OTHERS THEN v_fail := v_fail + 1; v_log := v_log || 'T1 FAIL ' || SQLERRM || ';';
  END;

  -- T2: cross-user claim
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid_b)::text, true);
  BEGIN
    PERFORM public.claim_payment_receipt('topup','TX111111', repeat('a',64), NULL, NULL, NULL, 5000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan1));
    v_fail := v_fail + 1; v_log := v_log || 'T2 FAIL cross-user accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%receipt_scan_not_found%' THEN v_pass := v_pass + 1; v_log := v_log || 'T2 PASS cross-user rejected;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T2 FAIL wrong err;'; END IF;
  END;

  -- T3: double claim
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid_a)::text, true);
  BEGIN
    PERFORM public.claim_payment_receipt('topup','TX111112', repeat('a',64), NULL, NULL, NULL, 5000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan1));
    v_fail := v_fail + 1; v_log := v_log || 'T3 FAIL double accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%receipt_scan_already_used%' THEN v_pass := v_pass + 1; v_log := v_log || 'T3 PASS double rejected;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T3 FAIL wrong err ' || SQLERRM || ';'; END IF;
  END;

  -- T4: fake client OCR must be overridden by server
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid_a)::text, true);
  BEGIN
    SELECT * INTO v_r FROM public.claim_payment_receipt('topup','TX222222', repeat('b',64), NULL, NULL, NULL, 3000, 999999, 'FAKE999', 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan2)) LIMIT 1;
    SELECT pr.amount_detected INTO v_amt FROM public.payment_receipts pr WHERE pr.id = v_r.id;
    IF v_amt = 3000 THEN v_pass := v_pass + 1; v_log := v_log || 'T4 PASS fake OCR overridden;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T4 FAIL stored=' || v_amt || ';'; END IF;
  EXCEPTION WHEN OTHERS THEN v_fail := v_fail + 1; v_log := v_log || 'T4 FAIL ' || SQLERRM || ';';
  END;

  -- T5: hash mismatch
  BEGIN
    PERFORM public.claim_payment_receipt('topup','TX444444', repeat('e',64), NULL, NULL, NULL, 4000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan4));
    v_fail := v_fail + 1; v_log := v_log || 'T5 FAIL hash mismatch accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%receipt_scan_hash_mismatch%' THEN v_pass := v_pass + 1; v_log := v_log || 'T5 PASS hash mismatch rejected;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T5 FAIL wrong err;'; END IF;
  END;

  -- T6: expired scan
  BEGIN
    PERFORM public.claim_payment_receipt('topup','TX333333', repeat('c',64), NULL, NULL, NULL, 7000, NULL, NULL, 'needs_review', NULL, '{}', jsonb_build_object('edge_scan_id', v_scan3));
    v_fail := v_fail + 1; v_log := v_log || 'T6 FAIL expired accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%receipt_scan_expired%' THEN v_pass := v_pass + 1; v_log := v_log || 'T6 PASS expired rejected;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T6 FAIL wrong err;'; END IF;
  END;

  RAISE EXCEPTION 'ADVRESULT % passed, % failed | %', v_pass, v_fail, v_log;
END $$;
