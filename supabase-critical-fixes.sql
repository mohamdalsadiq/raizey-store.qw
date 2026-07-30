-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — إصلاحات حرجة (يوليو 2026)
-- شغّل هذا الملف كاملاً في Supabase SQL Editor بعد supabase-security.sql
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
-- المشكلة المكتشفة:
-- الـ Trigger ودالة create_wallet_order كانتا تعتمدان على عمود
-- "products.price_sdg" وعلى مفتاح "price_sdg" داخل كل خيار فرعي —
-- وهذا العمود/المفتاح غير موجودَين إطلاقاً في التطبيق الفعلي؛ كل مكان
-- في الكود (admin-products.html, category.html, product.html) يحفظ
-- وستخدم "price_usd" فقط، والسعر بالجنيه يُحسب ديناميكياً من سعر
-- الصرف + هامش الربح المخزَّنين في جدول settings.
-- النتيجة: كل عملية شراء (محفظة أو تحويل بنكي) كانت تفشل بخطأ من
-- قاعدة البيانات، أو تتجاهل سعر الخيار الفرعي المختار تماماً.
-- ─────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────
-- PART 1: عمود field_labels — لحفظ الأسماء المقروءة لحقول الطلب
-- (بدل ظهور "field_17847295176537vg" بدل "رقم الواتساب" في لوحة الأدمن)
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS field_labels jsonb DEFAULT '{}'::jsonb;

-- ─────────────────────────────────────────────────────────────────────
-- PART 2: إصلاح Trigger التحقق من السعر — verify_order_price_before_insert
-- يحسب السعر المتوقع الآن من price_usd الحقيقي + سعر الصرف + هامش الربح،
-- ويقرأ price_usd الصحيح من الخيار الفرعي المختار (وليس price_sdg الوهمي)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_order_price_before_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_product_price_usd NUMERIC;
    v_rate            NUMERIC;
    v_margin          NUMERIC;
    v_option_price_usd NUMERIC;
    v_expected_price  NUMERIC;
BEGIN
    SELECT price_usd INTO v_product_price_usd
    FROM products
    WHERE id = NEW.product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'المنتج غير موجود';
    END IF;

    SELECT
      (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
      (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
    INTO v_rate, v_margin;

    v_rate   := COALESCE(v_rate,   0);
    v_margin := COALESCE(v_margin, 0);

    -- السعر الأساسي للمنتج (بالجنيه) من price_usd الحقيقي
    v_expected_price := v_product_price_usd * v_rate * (1 + v_margin / 100.0);

    -- إذا كان هناك خيار فرعي مختار، نحسب السعر منه بدلاً من السعر الأساسي
    -- (المفتاح الصحيح المستخدَم فعلياً في كل التطبيق هو price_usd وليس price_sdg)
    IF NEW.selected_option IS NOT NULL AND (NEW.selected_option->>'price_usd') IS NOT NULL THEN
        v_option_price_usd := (NEW.selected_option->>'price_usd')::NUMERIC;
        IF v_option_price_usd > 0 THEN
            v_expected_price := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
        END IF;
    END IF;

    -- السماح بالسعر المخفَّض بكوبون، لكن يُمنع أي سعر أقل من 5% من السعر
    -- المتوقع حتى مع وجود كوبون (لمنع التلاعب الكامل بالسعر عبر كوبون وهمي)
    IF NEW.coupon_id IS NULL AND NEW.price_sdg_snapshot < (v_expected_price * 0.99) THEN
        RAISE EXCEPTION 'عذراً، تم اكتشاف تلاعب في سعر الطلب!';
    END IF;

    IF NEW.coupon_id IS NOT NULL AND NEW.price_sdg_snapshot < (v_expected_price * 0.05) THEN
        RAISE EXCEPTION 'عذراً، تم اكتشاف تلاعب في سعر الطلب!';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_verify_order_price ON orders;
CREATE TRIGGER trg_verify_order_price
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION verify_order_price_before_insert();

-- ─────────────────────────────────────────────────────────────────────
-- PART 3: إصلاح كامل لدالة create_wallet_order
-- - يحسب السعر من price_usd الحقيقي (مو price_sdg غير الموجود)
-- - يحفظ الخيار الفرعي المختار فعلياً في عمود selected_option (كان NULL دائماً)
-- - يفرض اختيار خيار فرعي إجبارياً إذا كان المنتج يحتوي على خيارات
-- - يحفظ field_labels لعرضها بشكل مقروء للأدمن
-- ─────────────────────────────────────────────────────────────────────
-- ملاحظة: أضفنا معامل p_field_labels جديد، فتغيّر عدد المعاملات (4 → 5).
-- CREATE OR REPLACE وحدها لن تستبدل النسخة القديمة بعدد معاملات مختلف،
-- بل ستُنشئ نسخة إضافية (Overload) وتسبب تعارضاً عند الاستدعاء.
-- لذلك نحذف التوقيع القديم صراحة أولاً:
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id         uuid,
  p_field_values        jsonb DEFAULT '{}',
  p_field_labels        jsonb DEFAULT '{}',
  p_coupon_code         text  DEFAULT NULL,
  p_selected_option_id  text  DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        uuid := auth.uid();
  v_product        RECORD;
  v_wallet_balance NUMERIC;
  v_rate           NUMERIC;
  v_margin         NUMERIC;
  v_price_sdg      NUMERIC;
  v_option         jsonb := NULL;
  v_option_price_usd NUMERIC;
  v_coupon_id      uuid;
  v_discount_pct   numeric := 0;
  v_order_id       uuid;
  v_name_snapshot  text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;

  SELECT * INTO v_product FROM products WHERE id = p_product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  -- المنتج له خيارات فرعية؟ الاختيار يصبح إجبارياً حتى على مستوى السيرفر
  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF p_selected_option_id IS NULL OR trim(p_selected_option_id) = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id
    LIMIT 1;

    IF v_option IS NULL THEN
      RAISE EXCEPTION 'option_not_found';
    END IF;

    v_option_price_usd := COALESCE((v_option->>'price_usd')::NUMERIC, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_price_sdg := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || (v_option->>'label');
  ELSE
    v_price_sdg := v_product.price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
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

  v_price_sdg := ROUND(v_price_sdg);

  -- التحقق من رصيد المحفظة (مع قفل لمنع السحب المزدوج)
  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- خصم الرصيد
  UPDATE wallets SET balance = balance - v_price_sdg WHERE user_id = v_user_id;

  -- إنشاء الطلب — مع حفظ الخيار الفرعي وأسماء الحقول المقروءة فعلياً
  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id
  )
  VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'), COALESCE(p_field_labels, '{}'), v_option,
    'wallet', 'in_progress', v_coupon_id
  )
  RETURNING orders.id INTO v_order_id;

  RETURN QUERY SELECT v_order_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 4: إصلاح صلاحية إضافة سجلات audit_logs
-- السياسة القديمة صارت "أدمن فقط" بالكامل، وهذا كسر بصمت تسجيل تنبيهات
-- الاحتيال التلقائية من صفحة الدفع (checkout.html) التي يرسلها الزبون
-- نفسه (admin_id = NULL). هذي السياسة تعيد فتح الإدراج للزبون فقط في
-- حالة admin_id = NULL، وتمنع أي زبون من انتحال هوية أدمن حقيقي في السجل.
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "audit_logs_insert_customer" ON audit_logs;
CREATE POLICY "audit_logs_insert_customer" ON audit_logs
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND admin_id IS NULL);

-- ─────────────────────────────────────────────────────────────────────
-- ✅ انتهى — الملف جاهز للتشغيل في Supabase SQL Editor
-- ─────────────────────────────────────────────────────────────────────
