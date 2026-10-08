-- P1-FIN-001: server-side top-up amount binding in admin_confirm_topup.
--
-- Background (DBSEC2-001, confirmed live 2026-10-07):
--   admin_confirm_topup credited v_topup.amount (client-originated) with zero
--   comparison against the verified receipt. One admin mistake = phantom balance.
--
-- New invariant: a top-up whose linked receipt has amount_detected can only be
-- confirmed when |detected - requested| <= max(1%, 2), OR with an explicit
-- admin override reason that is written to the audit trail.
-- Top-ups without a linked/verified receipt keep the legacy path (logged).
--
-- NOTE: an older single-arg overload admin_confirm_topup(uuid) must be dropped,
-- otherwise Postgres resolves 1-arg calls to the OLD unchecked body.
--
-- SAFE: additive check, backward-compatible signature (new arg has DEFAULT).
-- ROLLBACK: re-apply the previous function body (loses the check).
-- APPLIED LIVE: 2026-10-08 (7 statements OK, old overload dropped, verified).

DROP FUNCTION IF EXISTS public.admin_confirm_topup(uuid);

CREATE OR REPLACE FUNCTION public.admin_confirm_topup(
  p_topup_id uuid,
  p_override_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup public.wallet_topups%ROWTYPE;
  v_detected numeric;
  v_diff numeric;
  v_tolerance numeric;
  v_overrode boolean := false;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_wallets') THEN
    RAISE EXCEPTION 'access_denied: manage_wallets permission required';
  END IF;

  SELECT * INTO v_topup FROM public.wallet_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'topup_not_found'; END IF;
  IF v_topup.status <> 'pending' THEN RAISE EXCEPTION 'already_processed'; END IF;

  -- Server-side binding: the credited amount must match the verified receipt.
  IF v_topup.receipt_id IS NOT NULL THEN
    SELECT pr.amount_detected INTO v_detected
    FROM public.payment_receipts pr
    WHERE pr.id = v_topup.receipt_id;
  END IF;

  IF v_detected IS NOT NULL THEN
    v_diff := abs(v_detected - v_topup.amount);
    v_tolerance := GREATEST(v_detected * 0.01, 2);
    IF v_diff > v_tolerance THEN
      IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
        RAISE EXCEPTION 'topup_amount_mismatch: receipt detected % but topup requests %',
          v_detected, v_topup.amount;
      END IF;
      v_overrode := true;
    END IF;
  END IF;

  UPDATE public.wallet_topups
  SET status = 'confirmed', reviewed_at = now()
  WHERE id = p_topup_id;

  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_topup.user_id, v_topup.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = public.wallets.balance + EXCLUDED.balance, updated_at = now();

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (v_topup.user_id, 'تم تأكيد شحن المحفظة', 'تمت إضافة مبلغ الشحن إلى محفظتك بنجاح.', 'wallet');

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (auth.uid(), 'تأكيد شحن محفظة',
    jsonb_build_object(
      'topup_id', p_topup_id,
      'user_id', v_topup.user_id,
      'amount', v_topup.amount,
      'amount_detected', v_detected,
      'amount_overridden', v_overrode,
      'override_reason', p_override_reason
    ),
    'admin_action');
END;
$$;

COMMENT ON FUNCTION public.admin_confirm_topup(uuid, text) IS
  'P1-FIN-001: top-up amount is bound server-side to the verified receipt (tolerance max(1%,2)); mismatches require an explicit audited override reason.';
