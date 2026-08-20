-- Task 7: live admin dashboard fixes
-- Idempotent migration for products/categories RLS and admin alert counts.

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS products_admin_all ON public.products;
CREATE POLICY products_admin_all ON public.products
  FOR ALL TO authenticated
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

DROP POLICY IF EXISTS categories_admin ON public.categories;
CREATE POLICY categories_admin ON public.categories
  FOR ALL TO authenticated
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

CREATE OR REPLACE FUNCTION public.get_admin_notification_counts()
RETURNS TABLE(
  pending_orders bigint,
  needs_admin_check bigint,
  pending_topups bigint,
  total_alerts bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending_orders bigint := 0;
  v_needs_check bigint := 0;
  v_pending_topups bigint := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  IF public.has_admin_permission('manage_orders') THEN
    SELECT COUNT(*) INTO v_pending_orders
    FROM public.orders
    WHERE status = 'pending_review';

    SELECT COUNT(*) INTO v_needs_check
    FROM public.orders
    WHERE status NOT IN ('cancelled', 'completed', 'rejected', 'pending_review')
      AND (
        ocr_status = 'needs_admin_check'
        OR NULLIF(btrim(COALESCE(review_reason, '')), '') IS NOT NULL
      );
  END IF;

  IF public.has_admin_permission('manage_wallets') THEN
    SELECT COUNT(*) INTO v_pending_topups
    FROM public.wallet_topups
    WHERE status = 'pending';
  END IF;

  RETURN QUERY SELECT
    v_pending_orders,
    v_needs_check,
    v_pending_topups,
    v_pending_orders + v_needs_check + v_pending_topups;
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_notification_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_notification_counts() TO authenticated;
