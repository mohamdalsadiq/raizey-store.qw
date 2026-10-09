-- ════════════════════════════════════════════════════════════════════════════
-- 2026-10-09 — admin_reject_order: align the repo with the LIVE database
-- ════════════════════════════════════════════════════════════════════════════
-- WHY THIS FILE EXISTS
--   The only in-repo definition of admin_reject_order lived in the retired
--   ad-hoc dump `deprecated/supabase-SQL-التوسعة-الإدارة-والعروض.sql` and it
--   still called the DROPPED refund signature:
--       admin_refund_wallet(v_order.user_id, v_order.price_sdg_snapshot, p_order_id)   -- 3 args (gone)
--   That 3-arg signature was removed by
--   supabase/migrations/20261008090000_p2_fin_001_refund_hardening.sql, which
--   replaced it with admin_refund_wallet(p_order_id uuid, p_reason text).
--   Re-applying the old dump would create a BROKEN admin_reject_order.
--
--   This file is now the single canonical source of truth and reproduces the
--   live definition exactly. It is idempotent (CREATE OR REPLACE).
--
-- APPLY: run the whole file in ONE transaction (see db/README.md).

CREATE OR REPLACE FUNCTION public.admin_reject_order(p_order_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  v_reason := left(v_reason, 500);

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.status NOT IN ('pending_review', 'in_progress') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.orders
  SET status = 'rejected', rejection_reason = v_reason, updated_at = now()
  WHERE id = p_order_id;

  IF v_order.payment_type = 'wallet' THEN
    PERFORM public.admin_refund_wallet(p_order_id, 'order_rejected: ' || v_reason);
  END IF;

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (
    v_order.user_id,
    'تم رفض طلبك',
    'طلبك (' || left(COALESCE(v_order.product_name_snapshot, 'المنتج'), 160) || ') رُفض. السبب: ' || v_reason,
    'order'
  );

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    'رفض طلب',
    jsonb_build_object('order_id', p_order_id, 'user_id', v_order.user_id, 'reason', v_reason, 'refunded', v_order.payment_type = 'wallet')
  );
END;
$function$;

-- Grants mirror the live ACL: authenticated may call it (the function enforces
-- admin + manage_orders internally). No PUBLIC/anon execution.
REVOKE ALL ON FUNCTION public.admin_reject_order(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_reject_order(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_order(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_reject_order(uuid, text) IS
  'Admin: reject an order with a mandatory reason; refunds the wallet when the order was paid from the wallet. Server-side enforcement (manage_orders).';
