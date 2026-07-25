-- =====================================================================
-- RAIZ3Y STORE — التصحيح الأمني النهائي (تشغيل في Supabase SQL Editor)
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. منع الإدراج المباشر في جدول orders (أهم تعديل أمني)
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "orders_insert_own" ON orders;
CREATE POLICY "orders_insert_deny" ON orders
  FOR INSERT WITH CHECK (false);

-- (اختياري: لو عايز الأدمن يضيف يدوياً، فك التعليق عن السطر التالي)
-- CREATE POLICY "orders_insert_admin" ON orders FOR INSERT WITH CHECK (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- 2. تحديث دالة create_wallet_order (إضافة FOR UPDATE + Audit Log)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id       uuid,
  p_field_values     jsonb    DEFAULT '{}',
  p_coupon_code      text     DEFAULT NULL,
  p_selected_option_id text   DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        uuid := auth.uid();
  v_product        RECORD;
  v_wallet_balance NUMERIC;
  v_price_sdg      NUMERIC;
  v_option_price   NUMERIC;
  v_coupon_id      uuid;
  v_discount_pct   numeric := 0;
  v_order_id       uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;

  -- 🔒 قفل صف المنتج لمنع تغيير السعر أثناء المعاملة
  SELECT * INTO v_product FROM products WHERE id = p_product_id AND is_active = true FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  -- حساب السعر من قاعدة البيانات (لا من الفرونت إند)
  v_price_sdg := v_product.price_sdg;

  IF p_selected_option_id IS NOT NULL AND p_selected_option_id != '' THEN
    SELECT (opt->>'price_sdg')::NUMERIC INTO v_option_price
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id;

    IF v_option_price IS NOT NULL AND v_option_price > 0 THEN
      v_price_sdg := v_option_price;
    END IF;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- تطبيق كوبون الخصم (ذرياً مع قفل الصف)
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) != '' THEN
    SELECT c.id, c.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   coupons c
    WHERE  upper(c.code) = upper(trim(p_coupon_code))
      AND  c.is_active = true
      AND  (c.usage_limit IS NULL OR c.usage_count < c.usage_limit)
      AND  (c.expires_at IS NULL OR c.expires_at > NOW())
    FOR UPDATE;

    IF FOUND THEN
      v_price_sdg := v_price_sdg * (1.0 - v_discount_pct / 100.0);
      UPDATE coupons SET usage_count = usage_count + 1 WHERE id = v_coupon_id;
    END IF;
  END IF;

  -- التحقق من رصيد المحفظة (مع قفل لمنع السحب المزدوج)
  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- خصم الرصيد
  UPDATE wallets SET balance = balance - v_price_sdg WHERE user_id = v_user_id;

  -- إنشاء الطلب
  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, selected_option,
    payment_type, status, coupon_id
  )
  VALUES (
    v_user_id, p_product_id, v_product.name,
    ROUND(v_price_sdg), p_field_values, NULL,
    'wallet', 'in_progress', v_coupon_id
  )
  RETURNING orders.id INTO v_order_id;

  -- 📝 تسجيل العملية في سجل التدقيق
  INSERT INTO audit_logs (admin_id, action, details)
  VALUES (NULL, 'wallet_order_created', jsonb_build_object(
    'order_id', v_order_id,
    'user_id', v_user_id,
    'amount', v_price_sdg,
    'coupon_id', v_coupon_id
  ));

  RETURN QUERY SELECT v_order_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. تحديث دالة use_coupon_atomic (إضافة Audit Log)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(p_code TEXT)
RETURNS TABLE(coupon_id UUID, discount_percent NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_coupon RECORD;
    v_user_id UUID := auth.uid();
BEGIN
    -- قفل الصف لمنع الاستخدام المتزامن
    SELECT * INTO v_coupon
    FROM coupons
    WHERE upper(code) = upper(trim(p_code))
      AND is_active = true
      AND (usage_limit IS NULL OR usage_count < usage_limit)
      AND (expires_at IS NULL OR expires_at > NOW())
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الكود غير صالح أو انتهت صلاحيته';
    END IF;

    UPDATE coupons
    SET usage_count = usage_count + 1
    WHERE id = v_coupon.id;

    -- 📝 تسجيل استخدام الكوبون
    INSERT INTO audit_logs (admin_id, action, details)
    VALUES (NULL, 'coupon_used', jsonb_build_object(
      'coupon_id', v_coupon.id,
      'user_id', v_user_id,
      'code', p_code
    ));

    RETURN QUERY SELECT
        v_coupon.id AS coupon_id,
        v_coupon.discount_percent AS discount_percent;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. دالة استبدال كود الهدية (لأنها كانت مفقودة في ملفك السابق)
-- ─────────────────────────────────────────────────────────────────────
-- تأكد من وجود جدول gift_cards
CREATE TABLE IF NOT EXISTS public.gift_cards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  amount NUMERIC NOT NULL,
  is_used BOOLEAN DEFAULT false,
  used_by UUID REFERENCES public.profiles(id) NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- تفعيل RLS على الجدول الجديد
ALTER TABLE IF EXISTS gift_cards ENABLE ROW LEVEL SECURITY;

-- سياسة: الأدمن فقط يقرأ
DROP POLICY IF EXISTS "gift_cards_admin_only" ON gift_cards;
CREATE POLICY "gift_cards_admin_only" ON gift_cards
  FOR ALL USING (public.is_admin());

-- الدالة
CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gift RECORD;
  v_user_id UUID := auth.uid();
  v_amount NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;

  -- قفل الصف لمنع الاستخدام المزدوج
  SELECT * INTO v_gift FROM gift_cards
  WHERE upper(code) = upper(trim(p_code)) AND is_used = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_code';
  END IF;

  -- تحديث حالة الكود
  UPDATE gift_cards SET
    is_used = true,
    used_by = v_user_id,
    used_at = NOW()
  WHERE id = v_gift.id;

  -- إضافة الرصيد للمحفظة
  UPDATE wallets SET balance = balance + v_gift.amount
  WHERE user_id = v_user_id;

  -- تسجيل العملية
  INSERT INTO audit_logs (admin_id, action, details)
  VALUES (NULL, 'gift_card_redeemed', jsonb_build_object(
    'user_id', v_user_id,
    'amount', v_gift.amount,
    'card_id', v_gift.id
  ));

  RETURN v_gift.amount;
END;
$$;
