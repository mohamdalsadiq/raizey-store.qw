-- P2-FIN-001: harden admin_refund_wallet — server-bound refund.
--
-- BEFORE: admin_refund_wallet(p_user_id, p_amount, p_order_id) accepted an arbitrary
-- amount and user from the caller — no binding to the order, no idempotency.
--
-- AFTER: admin_refund_wallet(p_order_id, p_reason):
--   1. user_id + amount are derived from the ORDER row (locked), never from the caller.
--   2. Idempotent: raises 'already_refunded' if orders.refunded is true.
--   3. Only completed orders can be refunded.
--   4. Writes wallet_transactions ledger row + audit_logs entry.
--   5. Grants remain admin-only (no anon/authenticated execute).
--
-- SAFE: no callers in the repo (verified 2026-10-08). Old signature dropped.
-- ROLLBACK: re-create the old 3-arg version (not recommended).
-- APPLIED LIVE: 2026-10-08.

DROP FUNCTION IF EXISTS public.admin_refund_wallet(uuid, numeric, uuid);

CREATE OR REPLACE FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order   public.orders%ROWTYPE;
  v_new_balance numeric;
  v_admin   uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_refund_input: order required';
  END IF;

  -- Lock the order; amount + user are server-derived from this row only.
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.refunded THEN
    RAISE EXCEPTION 'already_refunded';
  END IF;
  IF v_order.status <> 'completed' THEN
    RAISE EXCEPTION 'refund_not_allowed: status=%', v_order.status;
  END IF;
  IF v_order.price_sdg_snapshot IS NULL OR v_order.price_sdg_snapshot <= 0 THEN
    RAISE EXCEPTION 'invalid_refund_amount';
  END IF;

  UPDATE public.wallets
  SET balance = balance + v_order.price_sdg_snapshot, updated_at = now()
  WHERE user_id = v_order.user_id
  RETURNING balance INTO v_new_balance;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found for user %', v_order.user_id;
  END IF;

  UPDATE public.orders SET refunded = true WHERE id = p_order_id;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_order.user_id, v_order.price_sdg_snapshot, 'credit', v_new_balance, 'admin_refund', p_order_id, v_admin);

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (v_admin, 'admin_refund_wallet',
          jsonb_build_object('order_id', p_order_id,
                             'amount', v_order.price_sdg_snapshot,
                             'order_user_id', v_order.user_id,
                             'reason', NULLIF(trim(coalesce(p_reason, '')), '')),
          'admin_action');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_refund_wallet(uuid, text) FROM anon, authenticated;
COMMENT ON FUNCTION public.admin_refund_wallet(uuid, text) IS
  'P2-FIN-001: server-bound refund — amount/user derived from order, idempotent, admin-only.';
