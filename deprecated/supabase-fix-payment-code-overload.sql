-- ═══════════════════════════════════════════════════════════════════
-- Raizey — إصلاح خطأ PGRST203 في الدفع بالرمز
-- "Could not choose the best candidate function between
--  public.validate_payment_code(p_code ...)"
--
-- السبب: تراكم أكثر من نسخة (overload) من الدالة في القاعدة، لأن
-- الملفات السابقة كانت تحذف توقيع (text) فقط.
-- الحل: حذف كل النسخ ديناميكياً ثم إنشاء نسخة واحدة معتمدة.
--
-- شغّل هذا الملف كاملاً مرة واحدة في: Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════════════

-- ── STEP 1: حذف كل نسخ الدالتين مهما كان توقيعها ──
DO $cleanup$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('validate_payment_code', 'redeem_payment_code_order')
  LOOP
    RAISE NOTICE 'dropping %', r.sig;
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END
$cleanup$;

-- ── STEP 2: إنشاء النسخة المعتمدة الوحيدة ──
DROP FUNCTION IF EXISTS public.validate_payment_code(text);

CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_code    RECORD;
  v_norm    text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  v_norm := upper(btrim(coalesce(p_code, '')));
  IF length(v_norm) < 4 THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'cancelled' THEN
    RETURN QUERY SELECT false, 'cancelled'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'used' OR v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT false, 'already_used'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'expired'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id THEN
    RETURN QUERY SELECT false, 'not_your_code'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, v_code.amount, v_code.note;
END;
$$;

DROP FUNCTION IF EXISTS public.redeem_payment_code_order(text, jsonb, text);

CREATE OR REPLACE FUNCTION public.redeem_payment_code_order(
  p_code        text,
  p_items       jsonb,
  p_coupon_code text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id      uuid := auth.uid();
  v_norm         text;
  v_code         RECORD;
  v_updated      uuid;
  v_rate         numeric;
  v_margin       numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  v_last_id      uuid;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'cart_too_large';
  END IF;

  -- ── قفل الرمز أولاً ──
  v_norm := upper(btrim(coalesce(p_code, '')));
  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  FOR UPDATE;

  IF NOT FOUND                                             THEN RAISE EXCEPTION 'not_found';     END IF;
  IF v_code.status = 'cancelled'                            THEN RAISE EXCEPTION 'cancelled';     END IF;
  IF v_code.status <> 'active' OR v_code.used_by IS NOT NULL THEN RAISE EXCEPTION 'already_used'; END IF;
  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN RAISE EXCEPTION 'expired'; END IF;
  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id   THEN RAISE EXCEPTION 'not_your_code'; END IF;

  -- ── حساب الأسعار من القاعدة فقط ──
  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN
      RAISE EXCEPTION 'invalid_quantity';
    END IF;

    SELECT p.* INTO v_product FROM products p
    WHERE p.id = (v_item->>'product_id')::uuid AND p.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(btrim(v_item->>'option_id'), '') = '' THEN
        RAISE EXCEPTION 'option_required';
      END IF;

      SELECT opt INTO v_option
      FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id')
      LIMIT 1;

      IF v_option IS NULL THEN
        RAISE EXCEPTION 'option_not_found';
      END IF;

      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN
        RAISE EXCEPTION 'price_calculation_error';
      END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  -- ── قيمة الرمز يجب أن تغطي الإجمالي (تحقق في السيرفر لا المتصفح) ──
  IF COALESCE(v_code.amount, 0) < v_total THEN
    RAISE EXCEPTION 'amount_too_low';
  END IF;

  -- ── إدخال الطلبات ──
  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'code', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids     := array_append(v_ids, v_order_id);
      v_last_id := v_order_id;
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  -- ── استهلاك الرمز شرطياً: الحاجز الحقيقي ضد الاستخدام المزدوج ──
  UPDATE public.payment_codes pc
  SET status = 'used', used_by = v_user_id, used_at = now(), order_id = v_last_id
  WHERE pc.id = v_code.id AND pc.status = 'active' AND pc.used_by IS NULL
  RETURNING pc.id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'already_used';
  END IF;

  RETURN QUERY SELECT unnest(v_ids);
END;
$$;

-- ── STEP 3: الصلاحيات (anon لا ينفّذ أي دالة مالية) ──
REVOKE ALL ON FUNCTION public.validate_payment_code(text)                        FROM anon, public;
REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)       FROM anon, public;
GRANT EXECUTE ON FUNCTION public.validate_payment_code(text)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)    TO authenticated;

-- ── STEP 4: تقرير تحقق — يجب أن يكون العدد 1 لكل دالة ──
SELECT p.proname AS function_name,
       count(*)  AS versions,
       CASE WHEN count(*) = 1 THEN '✅ سليم' ELSE '❌ ما زال هناك تعدد' END AS status
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('validate_payment_code', 'redeem_payment_code_order')
GROUP BY p.proname;

-- ملاحظة مهمة: لا تُعِد تشغيل supabase-critical-fixes-7.sql بعد هذا الملف،
-- فهو يُنشئ نسخة قديمة بثلاثة أعمدة وسيُعيد المشكلة.
