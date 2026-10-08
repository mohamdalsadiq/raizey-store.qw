DO $$
DECLARE
  v_admin_id uuid;
  v_order1 uuid; v_order2 uuid;
  v_pass int := 0; v_fail int := 0;
  v_log text := '';
BEGIN
  -- find an admin user
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' LIMIT 1;
  PERFORM set_config('raizey.trusted_order', 'on', true);
  -- create test orders (completed, not refunded)
  INSERT INTO public.orders (user_id, status, price_sdg_snapshot, refunded, product_name_snapshot, field_values, payment_type)
  VALUES (v_admin_id, 'completed', 5000, false, 'test', '{}', 'bank') RETURNING id INTO v_order1;
  INSERT INTO public.orders (user_id, status, price_sdg_snapshot, refunded, product_name_snapshot, field_values, payment_type)
  VALUES (v_admin_id, 'completed', 3000, true, 'test', '{}', 'bank') RETURNING id INTO v_order2;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- T1: valid refund
  BEGIN
    PERFORM public.admin_refund_wallet(v_order1, 'test reason');
    IF EXISTS (SELECT 1 FROM public.orders WHERE id = v_order1 AND refunded) THEN
      v_pass := v_pass + 1; v_log := v_log || 'T1 PASS valid refund;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T1 FAIL not marked;'; END IF;
  EXCEPTION WHEN OTHERS THEN v_fail := v_fail + 1; v_log := v_log || 'T1 FAIL ' || SQLERRM || ';';
  END;

  -- T2: double refund (idempotency)
  BEGIN
    PERFORM public.admin_refund_wallet(v_order1, 'again');
    v_fail := v_fail + 1; v_log := v_log || 'T2 FAIL double accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%already_refunded%' THEN v_pass := v_pass + 1; v_log := v_log || 'T2 PASS idempotent;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T2 FAIL wrong err;'; END IF;
  END;

  -- T3: already-refunded order
  BEGIN
    PERFORM public.admin_refund_wallet(v_order2, 'test');
    v_fail := v_fail + 1; v_log := v_log || 'T3 FAIL accepted;';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%already_refunded%' THEN v_pass := v_pass + 1; v_log := v_log || 'T3 PASS rejected;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T3 FAIL wrong err;'; END IF;
  END;

  -- T4: ledger + audit written
  BEGIN
    IF EXISTS (SELECT 1 FROM public.wallet_transactions WHERE reference_id = v_order1 AND source = 'admin_refund')
       AND EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'admin_refund_wallet'
                   AND details->>'order_id' = v_order1::text) THEN
      v_pass := v_pass + 1; v_log := v_log || 'T4 PASS ledger+audit;';
    ELSE v_fail := v_fail + 1; v_log := v_log || 'T4 FAIL missing rows;'; END IF;
  END;

  RAISE EXCEPTION 'REFUNDRESULT % passed, % failed | %', v_pass, v_fail, v_log;
END $$;
