-- RAIZEY STORE — الإدارة، التنبيهات، الأكثر شراءً، وصلاحيات المشرفين
-- هذه migration لا تُطبّق تلقائيًا. راجعها وشغّلها في Supabase SQL Editor بعد أخذ نسخة احتياطية.

CREATE INDEX IF NOT EXISTS idx_orders_completed_product
  ON public.orders (product_id, created_at DESC)
  WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_products_active_flash_sale
  ON public.products (is_active, flash_sale_ends_at)
  WHERE flash_sale_ends_at IS NOT NULL;

-- منتجات الأكثر شراءً: نعيد أقل قدر من البيانات اللازمة للواجهة العامة فقط.
CREATE OR REPLACE FUNCTION public.get_popular_products(p_limit integer DEFAULT 8)
RETURNS TABLE (
  product_id uuid,
  category_id uuid,
  name text,
  description text,
  image_url text,
  price_usd numeric,
  compare_at_price_usd numeric,
  flash_sale_ends_at timestamptz,
  delivery_badge_text text,
  purchase_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.category_id,
    p.name,
    p.description,
    p.image_url,
    p.price_usd,
    p.compare_at_price_usd,
    p.flash_sale_ends_at,
    p.delivery_badge_text,
    COUNT(o.id)::bigint AS purchase_count
  FROM public.products p
  LEFT JOIN public.orders o
    ON o.product_id = p.id
   AND o.status = 'completed'
  WHERE p.is_active = true
  GROUP BY p.id
  ORDER BY COUNT(o.id) DESC, p.display_order ASC, p.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 8), 1), 24);
$$;

REVOKE ALL ON FUNCTION public.get_popular_products(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.get_popular_products(integer) TO anon, authenticated;

-- عدادات الإدارة: لا تُرجع أي بيانات حساسة، وتُحجب عن غير الإداريين.
CREATE OR REPLACE FUNCTION public.get_admin_notification_counts()
RETURNS TABLE (
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
    WHERE ocr_status = 'needs_admin_check'
       OR NULLIF(btrim(COALESCE(review_reason, '')), '') IS NOT NULL;
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

REVOKE ALL ON FUNCTION public.get_admin_notification_counts() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_admin_notification_counts() TO authenticated;

-- تغيير حالات الطلبات عبر مسار ذري ومحدد الانتقالات.
CREATE OR REPLACE FUNCTION public.admin_update_order_status(
  p_order_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_status text := lower(btrim(COALESCE(p_status, '')));
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;

  IF v_status NOT IN ('in_progress', 'completed', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_status = 'in_progress' AND v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF v_status = 'completed' AND v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF v_status = 'cancelled' AND v_order.status NOT IN ('pending_review', 'in_progress') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.orders
  SET status = v_status, updated_at = now()
  WHERE id = p_order_id;

  IF v_status = 'cancelled'
     AND v_order.payment_type = 'wallet'
     AND COALESCE(v_order.refunded, false) = false THEN
    PERFORM public.admin_refund_wallet(v_order.user_id, v_order.price_sdg_snapshot, p_order_id);
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    'تغيير حالة طلب',
    jsonb_build_object('order_id', p_order_id, 'from', v_order.status, 'to', v_status)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_order_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_order_status(uuid, text) TO authenticated;

-- رفض الطلب: يثبت السبب ويعيد رصيد طلب المحفظة ذريًا عند الحاجة.
CREATE OR REPLACE FUNCTION public.admin_reject_order(
  p_order_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    PERFORM public.admin_refund_wallet(v_order.user_id, v_order.price_sdg_snapshot, p_order_id);
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
$$;

REVOKE ALL ON FUNCTION public.admin_reject_order(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_order(uuid, text) TO authenticated;

-- تأكيد الشحن يجب أن يتطلب صلاحية المحافظ، لا مجرد role=admin.
CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup public.wallet_topups%ROWTYPE;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_wallets') THEN
    RAISE EXCEPTION 'access_denied: manage_wallets permission required';
  END IF;

  SELECT * INTO v_topup FROM public.wallet_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'topup_not_found'; END IF;
  IF v_topup.status <> 'pending' THEN RAISE EXCEPTION 'already_processed'; END IF;

  UPDATE public.wallet_topups
  SET status = 'confirmed', reviewed_at = now()
  WHERE id = p_topup_id;

  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_topup.user_id, v_topup.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = public.wallets.balance + EXCLUDED.balance, updated_at = now();

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (v_topup.user_id, 'تم تأكيد شحن المحفظة', 'تمت إضافة مبلغ الشحن إلى محفظتك بنجاح.', 'wallet');

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (auth.uid(), 'تأكيد شحن محفظة', jsonb_build_object('topup_id', p_topup_id, 'user_id', v_topup.user_id, 'amount', v_topup.amount));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_topup(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_confirm_topup(uuid) TO authenticated;

-- حظر العملاء يمر عبر صلاحية إدارة المشرفين، مع منع حظر الحساب المنفذ.
CREATE OR REPLACE FUNCTION public.admin_set_customer_banned(
  p_profile_id uuid,
  p_banned boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_admins') THEN
    RAISE EXCEPTION 'access_denied: manage_admins permission required';
  END IF;
  IF p_profile_id IS NULL OR p_profile_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot_modify_self';
  END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  UPDATE public.profiles SET is_banned = COALESCE(p_banned, false) WHERE id = p_profile_id;
  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (auth.uid(), CASE WHEN p_banned THEN 'حظر عميل' ELSE 'إلغاء حظر عميل' END, jsonb_build_object('target_id', p_profile_id, 'banned', p_banned));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_customer_banned(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_customer_banned(uuid, boolean) TO authenticated;

-- إدارة المشرفين: لا يمكن تعديل حساب المنفذ أو إزالة آخر سوبر أدمن.
CREATE OR REPLACE FUNCTION public.admin_set_staff_permissions(
  p_profile_id uuid,
  p_role text,
  p_permissions jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := lower(btrim(COALESCE(p_role, '')));
  v_all boolean := lower(COALESCE(p_permissions->>'all', 'false')) = 'true';
  v_is_super boolean := v_all OR lower(COALESCE(p_permissions->>'is_super_admin', 'false')) = 'true';
  v_target_role text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'access_denied: super admin required';
  END IF;
  IF p_profile_id IS NULL OR p_profile_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot_modify_self';
  END IF;
  IF v_role NOT IN ('admin', 'customer') THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  SELECT role INTO v_target_role FROM public.profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;

  IF v_role = 'customer' THEN
    IF v_target_role = 'admin' AND EXISTS (
      SELECT 1 FROM public.admin_permissions WHERE profile_id = p_profile_id AND is_super_admin = true
    ) THEN
      IF (SELECT COUNT(*) FROM public.admin_permissions WHERE is_super_admin = true) <= 1 THEN
        RAISE EXCEPTION 'cannot_remove_last_super_admin';
      END IF;
    END IF;
    UPDATE public.profiles SET role = 'customer' WHERE id = p_profile_id;
    DELETE FROM public.admin_permissions WHERE profile_id = p_profile_id;
  ELSE
    UPDATE public.profiles SET role = 'admin' WHERE id = p_profile_id;
    INSERT INTO public.admin_permissions (
      profile_id, is_super_admin, can_manage_orders, can_manage_wallets, can_manage_products,
      can_manage_settings, can_manage_maintenance, can_manage_admins, can_manage_coupons,
      can_manage_gift_cards, can_view_audit_logs, created_by, updated_by
    ) VALUES (
      p_profile_id, v_is_super, v_all OR lower(COALESCE(p_permissions->>'can_manage_orders', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_wallets', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_products', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_settings', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_maintenance', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_admins', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_coupons', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_gift_cards', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_view_audit_logs', 'false')) = 'true',
      auth.uid(), auth.uid()
    )
    ON CONFLICT (profile_id) DO UPDATE SET
      is_super_admin = EXCLUDED.is_super_admin,
      can_manage_orders = EXCLUDED.can_manage_orders,
      can_manage_wallets = EXCLUDED.can_manage_wallets,
      can_manage_products = EXCLUDED.can_manage_products,
      can_manage_settings = EXCLUDED.can_manage_settings,
      can_manage_maintenance = EXCLUDED.can_manage_maintenance,
      can_manage_admins = EXCLUDED.can_manage_admins,
      can_manage_coupons = EXCLUDED.can_manage_coupons,
      can_manage_gift_cards = EXCLUDED.can_manage_gift_cards,
      can_view_audit_logs = EXCLUDED.can_view_audit_logs,
      updated_by = auth.uid(), updated_at = now();
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (auth.uid(), 'تحديث صلاحيات مشرف', jsonb_build_object('target_id', p_profile_id, 'role', v_role, 'is_super_admin', v_is_super));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_staff_permissions(uuid, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_staff_permissions(uuid, text, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ربط جداول الإدارة بالصلاحيات الدقيقة بدل role=admin العام.
DROP POLICY IF EXISTS products_admin_all ON public.products;
CREATE POLICY products_admin_all
  ON public.products FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

DROP POLICY IF EXISTS categories_admin_all ON public.categories;
CREATE POLICY categories_admin_all
  ON public.categories FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

DROP POLICY IF EXISTS coupons_admin ON public.coupons;
CREATE POLICY coupons_admin
  ON public.coupons FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_coupons'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_coupons'));

DROP POLICY IF EXISTS coupons_select_admin_only ON public.coupons;
CREATE POLICY coupons_select_admin_only
  ON public.coupons FOR SELECT
  USING (public.is_admin() AND public.has_admin_permission('manage_coupons'));

DROP POLICY IF EXISTS gift_cards_admin ON public.gift_cards;
CREATE POLICY gift_cards_admin
  ON public.gift_cards FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_gift_cards'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_gift_cards'));

DROP POLICY IF EXISTS payment_methods_admin ON public.payment_methods;
CREATE POLICY payment_methods_admin
  ON public.payment_methods FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_settings'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_settings'));

DROP POLICY IF EXISTS payment_methods_select ON public.payment_methods;
CREATE POLICY payment_methods_select
  ON public.payment_methods FOR SELECT
  USING (is_active = true OR (public.is_admin() AND public.has_admin_permission('manage_settings')));

DROP POLICY IF EXISTS settings_admin ON public.settings;
CREATE POLICY settings_admin
  ON public.settings FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_settings'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_settings'));

NOTIFY pgrst, 'reload schema';

-- تشديد رموز الدفع ومستويات الإحالة على الصلاحية الدقيقة.
DROP POLICY IF EXISTS "admins manage payment codes" ON public.payment_codes;
DROP POLICY IF EXISTS payment_codes_admin_all ON public.payment_codes;
CREATE POLICY payment_codes_admin_manage
  ON public.payment_codes FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_settings'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_settings'));

DROP POLICY IF EXISTS referral_milestones_admin ON public.referral_milestones;
CREATE POLICY referral_milestones_admin
  ON public.referral_milestones FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_settings'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_settings'));

NOTIFY pgrst, 'reload schema';
