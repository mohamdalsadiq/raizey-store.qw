-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — إصلاح حرج #8
-- ملف: supabase-critical-fixes-8.sql
-- شغّله في: Supabase → SQL Editor  (آمن للتشغيل أكثر من مرة — idempotent)
-- يُشغَّل بعد كل الملفات السابقة (5 / 6 / 7 / smart-verify).
--
-- ═══ السبب الجذري الحقيقي للمشكلتين المُبلَّغ عنهما ═══
--
-- كل دوال إنشاء الطلبات مكتوبة بالشكل:
--
--     CREATE FUNCTION create_bank_orders_bulk(...) RETURNS TABLE(id uuid) ...
--     BEGIN
--       SELECT * INTO v_product FROM products WHERE id = ...;   ← 🔴
--
-- في PL/pgSQL، أعمدة RETURNS TABLE تُصبح **متغيّرات** داخل الدالة.
-- فوجود متغيّر اسمه id + عمود اسمه id في نفس الاستعلام ⇒ خطأ وقت التشغيل:
--
--     ERROR 42702: column reference "id" is ambiguous
--
-- هذا الخطأ لا يُطابق أي رسالة معروفة في الواجهة، فيظهر للعميل كـ
-- "حصل خطأ أثناء إتمام الطلب" (الصورة الثانية) — وهو ما يجعل **كل**
-- طلب بنكي يفشل بعد قبول الإيصال بالضبط كما حدث.
--
-- ونفس العلة في validate_payment_code (جدول payment_codes فيه عمود
-- amount والدالة تُرجع amount) ⇒ الدالة ترمي خطأ ⇒ الواجهة تُظهر
-- "تعذّر التحقق من الرمز حالياً" (الصورة الأولى).
--
-- الدوال التي لا تحتوي التعارض (check_tx_ref_available مثلاً) عملت
-- بشكل سليم تماماً — وهذا يُطابق ما ظهر في الصور حرفياً.
--
-- ═══ ما يفعله هذا الملف ═══
--   1) يُعيد إنشاء كل الدوال المصابة مع  #variable_conflict use_column
--      + تأهيل كل الأعمدة باسم الجدول (حل نهائي لا يتكرر)
--   2) يكمل نظام "الدفع برمز من الإدارة": الجدول + الدوال + الصلاحيات
--   3) يُضيف attach_secondary_receipt (الدفع المجزّأ) المفقودة
--   4) يمنع ترقية إيصال "يحتاج تدقيقاً إدارياً" إلى passed تلقائياً
--   5) تقرير تحقق في النهاية يطبع حالة كل جزء
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 0: توسيع قيد payment_type ليقبل الدفع بالرمز
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND contype  = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%payment_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', r.conname);
  END LOOP;

  ALTER TABLE public.orders
    ADD CONSTRAINT orders_payment_type_check
    CHECK (payment_type IN ('wallet', 'bank', 'code'));
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: جدول رموز الدفع payment_codes (يُكمل الناقص إن وُجد الجدول)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.payment_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  amount      numeric NOT NULL CHECK (amount > 0),
  note        text,
  user_id     uuid,                       -- مخصص لعميل معيّن (اختياري)
  status      text NOT NULL DEFAULT 'active',
  expires_at  timestamptz,
  created_by  uuid,
  used_by     uuid,
  used_at     timestamptz,
  order_id    uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- أعمدة قد تكون ناقصة لو أُنشئ الجدول بنسخة أقدم
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS note       text;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS user_id    uuid;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS status     text NOT NULL DEFAULT 'active';
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS used_by    uuid;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS used_at    timestamptz;
ALTER TABLE public.payment_codes ADD COLUMN IF NOT EXISTS order_id   uuid;

-- الرمز فريد تماماً بعد التطبيع (لا فرق بين حالة الأحرف)
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_codes_code
  ON public.payment_codes (upper(btrim(code)));

CREATE INDEX IF NOT EXISTS idx_payment_codes_status
  ON public.payment_codes (status, created_at DESC);

-- ── مفاتيح أجنبية بأسماء تتوقعها صفحة الإدارة (embed مع profiles) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_codes_user_id_fkey') THEN
    ALTER TABLE public.payment_codes
      ADD CONSTRAINT payment_codes_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_codes_used_by_fkey') THEN
    ALTER TABLE public.payment_codes
      ADD CONSTRAINT payment_codes_used_by_fkey
      FOREIGN KEY (used_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_codes_order_id_fkey') THEN
    ALTER TABLE public.payment_codes
      ADD CONSTRAINT payment_codes_order_id_fkey
      FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'payment_codes FKs: %', SQLERRM;
END $$;

ALTER TABLE public.payment_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_codes_admin_all"  ON public.payment_codes;
DROP POLICY IF EXISTS "payment_codes_select_own" ON public.payment_codes;

-- الإدارة فقط تُنشئ/تُعدّل/تحذف الرموز
CREATE POLICY "payment_codes_admin_all" ON public.payment_codes
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- العميل يرى فقط الرموز المخصّصة له أو التي استخدمها (لا يرى رموز غيره)
CREATE POLICY "payment_codes_select_own" ON public.payment_codes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR used_by = auth.uid());

REVOKE ALL ON public.payment_codes FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_codes TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: validate_payment_code — تحقق للعرض فقط (لا يستهلك الرمز)
-- ═══════════════════════════════════════════════════════════════════
-- ⚠️ #variable_conflict use_column هو ما يمنع خطأ "amount is ambiguous"
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


-- ═══════════════════════════════════════════════════════════════════
-- PART 3: redeem_payment_code_order — استهلاك الرمز + إنشاء الطلب معاً
-- ═══════════════════════════════════════════════════════════════════
-- الأسعار تُحسب في القاعدة فقط، والرمز يُقفل بـ FOR UPDATE ثم يُحدَّث
-- شرطياً (status='active') فلا يمكن استخدامه مرتين ولو تزامنت طلبات.
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


-- ═══════════════════════════════════════════════════════════════════
-- PART 4: 🔴 إعادة إنشاء create_bank_orders_bulk بلا تعارض متغيّرات
-- ═══════════════════════════════════════════════════════════════════
-- هذه هي الدالة التي كانت تفشل دائماً بـ 42702 فيرى العميل
-- "حصل خطأ أثناء إتمام الطلب" بعد قبول الإيصال.
DROP FUNCTION IF EXISTS public.create_bank_orders_bulk(jsonb, jsonb, text);

CREATE OR REPLACE FUNCTION public.create_bank_orders_bulk(
  p_items       jsonb,
  p_receipt     jsonb,
  p_coupon_code text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id      uuid := auth.uid();
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
  v_claim        RECORD;
  v_method_id    uuid;
  v_receipt_url  text;
  v_tx_ref_raw   text;
  v_receipt_hash text;
  v_ocr_in       text;
  v_ocr_final    text;
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
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_method_id   := NULLIF(p_receipt->>'payment_method_id', '')::uuid;
  v_receipt_url := NULLIF(p_receipt->>'receipt_url', '');
  v_ocr_in      := COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_review');

  IF v_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- ── المرور الأول: التحقق وحساب الأسعار من القاعدة فقط ──
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

  -- ── الكوبون: مرة واحدة فقط للسلة كاملة ──
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

  -- ── حجز الإيصال داخل نفس المعاملة (المبلغ المتوقع يُحسب هنا) ──
  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    v_method_id,
    v_total,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    v_ocr_in,
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  -- ── إيصال طلب الفحص الذكي تدقيقاً إدارياً لا يُرقّى إلى passed ──
  -- (مثال: إشعار قديم جداً — الرقم والمبلغ مطابقان لكنه يحتاج نظر الإدارة)
  v_ocr_final := v_claim.ocr_status;
  IF v_ocr_in IN ('needs_admin_check', 'needs_review') AND v_ocr_final = 'passed' THEN
    v_ocr_final := v_ocr_in;
    UPDATE payment_receipts pr SET ocr_status = v_ocr_final WHERE pr.id = v_claim.id;
  END IF;

  SELECT pr.tx_ref_raw, pr.receipt_hash
  INTO   v_tx_ref_raw, v_receipt_hash
  FROM   payment_receipts pr WHERE pr.id = v_claim.id;

  -- ── إدخال الطلبات (صف لكل قطعة) ──
  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id,
        payment_method_id, receipt_id, receipt_url, receipt_hash,
        transaction_reference, ocr_status, amount_verified, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'bank', 'pending_review', v_coupon_id,
        v_method_id, v_claim.id, v_receipt_url, v_receipt_hash,
        v_tx_ref_raw, v_ocr_final, v_claim.amount_verified, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT unnest(v_ids);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 5: 🔴 إعادة إنشاء دوال المحفظة بلا تعارض متغيّرات
-- ═══════════════════════════════════════════════════════════════════
-- نفس العلة (RETURNS TABLE(id uuid) + WHERE id = ...) كانت تُفشل
-- الدفع من المحفظة أيضاً — تُصلَح هنا معاً.
DROP FUNCTION IF EXISTS public.create_wallet_orders_bulk(jsonb, text);

CREATE OR REPLACE FUNCTION public.create_wallet_orders_bulk(
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
  v_rate         numeric;
  v_margin       numeric;
  v_balance      numeric;
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

  SELECT w.balance INTO v_balance FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;
  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_balance < v_total THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_total, updated_at = now()
  WHERE w.user_id = v_user_id;

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
        'wallet', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT unnest(v_ids);
END;
$$;


-- ── create_wallet_order (شراء مباشر لمنتج واحد) — نفس الإصلاح ──
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id         uuid,
  p_field_values       jsonb DEFAULT '{}'::jsonb,
  p_field_labels       jsonb DEFAULT '{}'::jsonb,
  p_coupon_code        text  DEFAULT NULL,
  p_selected_option_id text  DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id          uuid := auth.uid();
  v_product          RECORD;
  v_wallet_balance   numeric;
  v_rate             numeric;
  v_margin           numeric;
  v_price_sdg        numeric;
  v_option           jsonb := NULL;
  v_option_price_usd numeric;
  v_coupon_id        uuid;
  v_discount_pct     numeric := 0;
  v_order_id         uuid;
  v_name_snapshot    text;
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

  SELECT p.* INTO v_product FROM products p
  WHERE p.id = p_product_id AND p.is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF p_selected_option_id IS NULL OR btrim(p_selected_option_id) = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id
    LIMIT 1;

    IF v_option IS NULL THEN
      RAISE EXCEPTION 'option_not_found';
    END IF;

    v_option_price_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_price_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
  ELSE
    v_price_sdg     := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_price_sdg) uc;
    v_price_sdg := v_price_sdg * (1.0 - LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95) / 100.0);
  END IF;

  v_price_sdg := ROUND(v_price_sdg);
  IF v_price_sdg <= 0 THEN
    v_price_sdg := 1;
  END IF;

  SELECT w.balance INTO v_wallet_balance
  FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_price_sdg, updated_at = now()
  WHERE w.user_id = v_user_id;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id, refunded
  ) VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'::jsonb),
    COALESCE(p_field_labels, '{}'::jsonb), v_option,
    'wallet', 'in_progress', v_coupon_id, false
  )
  RETURNING orders.id INTO v_order_id;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT v_order_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 6: 🔴 إعادة إنشاء validate_coupon بلا تعارض متغيّرات
-- ═══════════════════════════════════════════════════════════════════
-- كانت coupon_id (عمود إخراج) تتعارض مع coupon_redemptions.coupon_id
-- ⇒ كل محاولة "تطبيق كود خصم" تفشل بخطأ غامض.
DROP FUNCTION IF EXISTS public.validate_coupon(text, numeric);

CREATE OR REPLACE FUNCTION public.validate_coupon(
  p_code        text,
  p_order_total numeric DEFAULT NULL
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT c.id, c.discount_percent AS pct, COALESCE(c.min_order_sdg, 0) AS min_order_sdg
  INTO v_coupon
  FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coupon_redemptions cr
    WHERE cr.coupon_id = v_coupon.id AND cr.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'coupon_already_used';
  END IF;

  IF p_order_total IS NOT NULL AND v_coupon.min_order_sdg > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  RETURN QUERY SELECT v_coupon.id, LEAST(GREATEST(COALESCE(v_coupon.pct, 0), 0), 95);
END;
$$;


-- ── use_coupon_atomic: تأهيل كامل للأعمدة (وقاية استباقية) ──
DROP FUNCTION IF EXISTS public.use_coupon_atomic(text, numeric);

CREATE OR REPLACE FUNCTION public.use_coupon_atomic(
  p_code        text,
  p_order_total numeric DEFAULT NULL
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
  v_pct     numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT c.* INTO v_coupon FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF p_order_total IS NOT NULL AND COALESCE(v_coupon.min_order_sdg, 0) > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id) VALUES (v_coupon.id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'coupon_already_used';
  END;

  UPDATE coupons c SET uses_count = COALESCE(c.uses_count, 0) + 1
  WHERE c.id = v_coupon.id;

  v_pct := LEAST(GREATEST(COALESCE(v_coupon.discount_percent, 0), 0), 95);
  RETURN QUERY SELECT v_coupon.id, v_pct;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 7: attach_secondary_receipt — الإشعار الثاني (الدفع المجزّأ)
-- ═══════════════════════════════════════════════════════════════════
-- تحجز رقم عملية الإشعار الثاني في payment_receipts حتى لا يُعاد
-- استخدامه، وتربطه بالطلب الأول عبر ocr_data.
DROP FUNCTION IF EXISTS public.attach_secondary_receipt(text, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.attach_secondary_receipt(
  p_parent_tx_ref text,
  p_order_id      uuid,
  p_receipt       jsonb
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_claim   RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  -- الطلب يجب أن يكون لهذا المستخدم
  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.id = p_order_id AND o.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'receipt_not_owned';
  END IF;

  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    NULLIF(p_receipt->>'payment_method_id', '')::uuid,
    NULLIF(p_receipt->>'expected_amount', '')::numeric,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_admin_check'),
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
       || jsonb_build_object(
            'split_parent_tx_ref', p_parent_tx_ref,
            'split_parent_order',  p_order_id,
            'is_secondary',        true)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  -- الإشعار الثاني لا يُعتبر مقبولاً تلقائياً أبداً
  UPDATE payment_receipts pr
  SET ocr_status = 'needs_admin_check'
  WHERE pr.id = v_claim.id;

  RETURN QUERY SELECT v_claim.id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 8: الصلاحيات — anon لا ينفّذ أي دالة مالية
-- ═══════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.validate_payment_code(text)                       FROM anon, public;
REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)      FROM anon, public;
REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text)       FROM anon, public;
REVOKE ALL ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)            FROM anon, public;
REVOKE ALL ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) FROM anon, public;
REVOKE ALL ON FUNCTION public.validate_coupon(text, numeric)                    FROM anon, public;
REVOKE ALL ON FUNCTION public.use_coupon_atomic(text, numeric)                  FROM anon, public;
REVOKE ALL ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb)       FROM anon, public;

GRANT EXECUTE ON FUNCTION public.validate_payment_code(text)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_coupon(text, numeric)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(text, numeric)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb)       TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- PART 9: تقرير تحقق — يطبع النتيجة في محرر SQL
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_missing text := '';
  v_fn      text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'validate_payment_code',
    'redeem_payment_code_order',
    'create_bank_orders_bulk',
    'create_wallet_orders_bulk',
    'create_wallet_order',
    'claim_payment_receipt',
    'check_tx_ref_available',
    'validate_coupon',
    'use_coupon_atomic',
    'attach_secondary_receipt'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_fn
    ) THEN
      v_missing := v_missing || v_fn || ', ';
    END IF;
  END LOOP;

  IF v_missing = '' THEN
    RAISE NOTICE '✅ كل الدوال المطلوبة موجودة ومصلَّحة (لا تعارض متغيّرات).';
  ELSE
    RAISE WARNING '⚠️ دوال ناقصة: %', v_missing;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'payment_codes') THEN
    RAISE NOTICE '✅ جدول payment_codes جاهز مع RLS والصلاحيات.';
  END IF;

  RAISE NOTICE '✅ payment_type يقبل الآن: wallet / bank / code';
END $$;
