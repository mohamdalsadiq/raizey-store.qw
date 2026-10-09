-- ============================================================================
-- RAIZEY STORE — customer order cancellation RPC
-- File: db/migrations/2026-10-08_user_cancel_order.sql
-- ============================================================================
-- Context: the storefront used a direct UPDATE on public.orders from the browser
-- (my-orders.html). Direct writes were revoked during the 2026-10-08 hardening,
-- so the mutation now lives in a minimal, auditable SECURITY DEFINER routine
-- that re-checks ownership and status server-side.
CREATE OR REPLACE FUNCTION public.cancel_my_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_order   public.orders%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_order';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.user_id <> v_user_id THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  -- wallet orders are charged up-front and move to in_progress immediately;
  -- refunding one is an admin decision (admin_update_order_status → cancel).
  IF v_order.payment_type = 'wallet' THEN
    RAISE EXCEPTION 'wallet_order_requires_support';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;
END
$fn$;

REVOKE EXECUTE ON FUNCTION public.cancel_my_order(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.cancel_my_order(uuid) TO authenticated;

SELECT 'user_cancel_order_applied' AS status;
