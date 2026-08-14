-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — الإصدار 21: سياسة التاريخ + التدقيق الإداري + رموز الدفع
-- ملف واحد يُشغَّل كاملاً في SQL Editor (آمن للتكرار)
-- ═══════════════════════════════════════════════════════════════════
-- 1) أعمدة سبب التدقيق على orders
-- 2) دعم الإشعار الثاني (دفع مجزّأ) على payment_receipts
-- 3) claim_payment_receipt: قبول حالة needs_admin_check
-- 4) create_bank_orders_bulk: حفظ سبب التدقيق مع الطلب
-- 5) attach_secondary_receipt: تسجيل إشعار المبلغ المتبقي وحجز رقمه
-- 6) payment_codes + validate_payment_code + redeem_payment_code_order
-- ═══════════════════════════════════════════════════════════════════

-- ── PART 1: أعمدة التدقيق ─────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS review_reason   text,
  ADD COLUMN IF NOT EXISTS review_severity text;

CREATE INDEX IF NOT EXISTS idx_orders_needs_admin_check
  ON public.orders (created_at DESC)
  WHERE ocr_status = 'needs_admin_check';

-- ── PART 2: ربط الإشعار الثاني بالأول ─────────────────────────────
ALTER TABLE public.payment_receipts
  ADD COLUMN IF NOT EXISTS parent_receipt_id uuid REFERENCES public.payment_receipts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_payment_receipts_parent
  ON public.payment_receipts (parent_receipt_id);

-- ── PART 3: claim_payment_receipt (نسخة تدعم needs_admin_check) ──
CREATE OR REPLACE FUNCTION public.claim_payment_receipt(
  p_purpose           text,
  p_tx_ref            text,
  p_receipt_hash      text,
  p_receipt_path      text    DEFAULT NULL,
  p_provider          text    DEFAULT NULL,
  p_payment_method_id uuid    DEFAULT NULL,
  p_amount_expected   numeric DEFAULT NULL,
  p_amount_detected   numeric DEFAULT NULL,
  p_tx_ref_ocr        text    DEFAULT NULL,
  p_ocr_status        text    DEFAULT 'needs_review',
  p_ocr_confidence    numeric DEFAULT NULL,
  p_risk_flags        text[]  DEFAULT '{}',
  p_ocr_data          jsonb   DEFAULT '{}'::jsonb
)
RETURNS TABLE(id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_norm     text;
  v_hash     text;
  v_amount_v boolean := false;
  v_ref_v    boolean := false;
  v_status   text;
  v_id       uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_purpose NOT IN ('order', 'topup') THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  v_hash := lower(trim(coalesce(p_receipt_hash, '')));

  -- رقم العملية: 6 خانات على الأقل (كل بنوك السودان أطول من ذلك)
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;
  -- بصمة SHA-256 = 64 خانة hex
  IF v_hash = '' OR v_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  -- الفحص الذكي رفض الإيصال → لا نحجزه ولا نُدخل طلباً
  IF coalesce(p_ocr_status, '') = 'rejected' THEN
    RAISE EXCEPTION 'receipt_rejected';
  END IF;

  -- ── فحص السجلات التاريخية (طلبات/شحنات أُدخلت قبل هذا النظام) ──
  IF EXISTS (
    SELECT 1 FROM orders
    WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) OR EXISTS (
    SELECT 1 FROM wallet_topups
    WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) THEN
    RAISE EXCEPTION 'duplicate_transaction_ref';
  END IF;

  IF EXISTS (SELECT 1 FROM orders        WHERE lower(receipt_hash) = v_hash)
  OR EXISTS (SELECT 1 FROM wallet_topups WHERE lower(receipt_hash) = v_hash) THEN
    RAISE EXCEPTION 'duplicate_receipt_image';
  END IF;

  -- ── حالة التحقق تُحسب في السيرفر لا في المتصفح ──
  IF p_amount_expected IS NOT NULL AND p_amount_detected IS NOT NULL
     AND p_amount_expected > 0 THEN
    -- هامش 1% أو 2 جنيه (أيهما أكبر) لتفادي فروق التقريب
    v_amount_v := abs(p_amount_detected - p_amount_expected)
                  <= GREATEST(p_amount_expected * 0.01, 2);
  END IF;

  v_ref_v := public.normalize_tx_ref(p_tx_ref_ocr) IS NOT NULL
             AND public.normalize_tx_ref(p_tx_ref_ocr) = v_norm;

  IF v_amount_v AND v_ref_v THEN
    -- تدقيق إداري مطلوب (إشعار قديم / دفع مجزّأ): يُقبل الطلب لكن يبقى موسوماً
    IF coalesce(p_ocr_status, '') = 'needs_admin_check' THEN
      v_status := 'needs_admin_check';
    ELSE
      v_status := 'passed';
    END IF;
  ELSIF coalesce(p_ocr_status, '') = 'needs_admin_check' THEN
    v_status := 'needs_admin_check';
  ELSE
    v_status := 'needs_review';
  END IF;

  -- ── الحجز الذرّي: القيود الفريدة هي الحاجز الحقيقي ──
  BEGIN
    INSERT INTO payment_receipts (
      user_id, purpose, provider, payment_method_id,
      tx_ref_raw, tx_ref_norm, tx_ref_ocr,
      receipt_hash, receipt_path,
      amount_expected, amount_detected,
      amount_verified, ref_verified,
      ocr_status, ocr_confidence, risk_flags, ocr_data
    ) VALUES (
      v_user_id, p_purpose, nullif(trim(coalesce(p_provider,'')),''), p_payment_method_id,
      trim(p_tx_ref), v_norm, nullif(trim(coalesce(p_tx_ref_ocr,'')),''),
      v_hash, p_receipt_path,
      p_amount_expected, p_amount_detected,
      v_amount_v, v_ref_v,
      v_status, p_ocr_confidence, coalesce(p_risk_flags, '{}'), coalesce(p_ocr_data, '{}'::jsonb)
    )
    RETURNING payment_receipts.id INTO v_id;
  EXCEPTION
    WHEN unique_violation THEN
      IF EXISTS (SELECT 1 FROM payment_receipts WHERE tx_ref_norm = v_norm) THEN
        RAISE EXCEPTION 'duplicate_transaction_ref';
      ELSE
        RAISE EXCEPTION 'duplicate_receipt_image';
      END IF;
  END;

  RETURN QUERY SELECT v_id, v_status, v_amount_v, v_ref_v;
END;
$$;


-- ── PART 4: create_bank_orders_bulk (يحفظ سبب التدقيق) ───────────
CREATE OR REPLACE FUNCTION public.create_bank_orders_bulk(
  p_items       jsonb,
  p_receipt     jsonb,
  p_coupon_code text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
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
  v_review_reason   text;
  v_review_severity text;
  v_receipt_hash text;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings WHERE maintenance_mode = true)
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

  v_method_id       := NULLIF(p_receipt->>'payment_method_id', '')::uuid;
  v_review_reason   := NULLIF(p_receipt->>'review_reason', '');
  v_review_severity := NULLIF(p_receipt->>'review_severity', '');
  v_receipt_url := NULLIF(p_receipt->>'receipt_url', '');

  IF v_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
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

    SELECT * INTO v_product FROM products
    WHERE id = (v_item->>'product_id')::uuid AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(trim(v_item->>'option_id'), '') = '' THEN
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

  -- ── الكوبون: مرة واحدة فقط للسلة كاملة (يرجع بالكامل لو فشل أي شيء بعده) ──
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  -- ── حجز الإيصال داخل نفس المعاملة ──
  -- المبلغ المتوقع يُحسب هنا في السيرفر (لا نأخذه من المتصفح إطلاقاً)
  SELECT * INTO v_claim
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
    COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_review'),
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
  );

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  SELECT tx_ref_raw, receipt_hash
  INTO   v_tx_ref_raw, v_receipt_hash
  FROM   payment_receipts WHERE id = v_claim.id;

  -- ── إدخال الطلبات (صف لكل قطعة) ──
  -- الأسعار محسوبة بالسيرفر، وبيانات الإيصال مأخوذة من صف الإيصال نفسه
  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id,
        payment_method_id, receipt_id, receipt_url, receipt_hash,
        transaction_reference, ocr_status, amount_verified, refunded,
        review_reason, review_severity
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
        v_tx_ref_raw, v_claim.ocr_status, v_claim.amount_verified, false,
        v_review_reason, v_review_severity
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT unnest(v_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) TO authenticated;


-- ── PART 5: attach_secondary_receipt — إشعار المبلغ المتبقي ───────
-- يحجز رقم العملية الثاني (فلا يُستخدم مرتين) ويربطه بالإيصال الأول.
CREATE OR REPLACE FUNCTION public.attach_secondary_receipt(
  p_parent_tx_ref text,
  p_order_id      uuid,
  p_receipt       jsonb
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_parent  uuid;
  v_claim   RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT id INTO v_parent
  FROM payment_receipts
  WHERE tx_ref_norm = public.normalize_tx_ref(p_parent_tx_ref)
    AND user_id = v_user_id
  LIMIT 1;

  IF v_parent IS NULL THEN
    RAISE EXCEPTION 'parent_receipt_not_found';
  END IF;

  SELECT * INTO v_claim
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
    'needs_admin_check',
    NULL,
    CASE WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
         THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
         ELSE '{}'::text[] END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
  );

  UPDATE payment_receipts
     SET parent_receipt_id = v_parent
   WHERE id = v_claim.id;

  -- كل طلبات نفس الإيصال الأول تُوسم بالتدقيق الإداري
  UPDATE orders
     SET ocr_status      = 'needs_admin_check',
         review_severity = COALESCE(review_severity, 'normal'),
         review_reason   = COALESCE(review_reason, 'دفع مجزّأ عبر إشعارين — يحتاج تدقيقاً إدارياً')
   WHERE receipt_id = v_parent AND user_id = v_user_id;

  RETURN v_claim.id;
END;
$$;

REVOKE ALL ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb) TO authenticated;


-- ── PART 6: رموز الدفع من الإدارة ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_codes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  amount     numeric NOT NULL CHECK (amount > 0),
  user_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note       text,
  status     text NOT NULL DEFAULT 'active'
             CHECK (status IN ('active', 'used', 'cancelled')),
  expires_at timestamptz,
  used_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  used_at    timestamptz,
  order_id   uuid,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_codes_status  ON public.payment_codes (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_codes_user    ON public.payment_codes (user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_codes TO authenticated;
GRANT ALL ON public.payment_codes TO service_role;

ALTER TABLE public.payment_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_codes_select_own" ON public.payment_codes;
DROP POLICY IF EXISTS "payment_codes_admin_all"  ON public.payment_codes;

-- العميل يرى الرموز المخصصة له فقط (ولا يستطيع تعديلها)
CREATE POLICY "payment_codes_select_own" ON public.payment_codes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR used_by = auth.uid() OR public.is_admin());

CREATE POLICY "payment_codes_admin_all" ON public.payment_codes
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- validate_payment_code — تحقق قبل الإرسال (قراءة فقط، لا يستهلك الرمز)
DROP FUNCTION IF EXISTS public.validate_payment_code(text);

CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
RETURNS TABLE(valid boolean, reason text, amount numeric)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row  RECORD;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_row FROM payment_codes
  WHERE upper(trim(code)) = upper(trim(coalesce(p_code, '')))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric; RETURN;
  END IF;
  IF v_row.status = 'used' THEN
    RETURN QUERY SELECT false, 'already_used'::text, NULL::numeric; RETURN;
  END IF;
  IF v_row.status = 'cancelled' THEN
    RETURN QUERY SELECT false, 'cancelled'::text, NULL::numeric; RETURN;
  END IF;
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RETURN QUERY SELECT false, 'expired'::text, NULL::numeric; RETURN;
  END IF;
  IF v_row.user_id IS NOT NULL AND v_row.user_id <> v_user THEN
    RETURN QUERY SELECT false, 'not_your_code'::text, NULL::numeric; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, v_row.amount;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_payment_code(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.validate_payment_code(text) TO authenticated;


-- redeem_payment_code_order — ذرّية: تستهلك الرمز وتنشئ الطلب معاً
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
  v_code         RECORD;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings WHERE maintenance_mode = true)
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

  -- ── قفل الرمز فوراً (FOR UPDATE) فيستحيل استخدامه مرتين ──
  SELECT * INTO v_code FROM payment_codes
  WHERE upper(trim(code)) = upper(trim(coalesce(p_code, '')))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF v_code.status = 'used'      THEN RAISE EXCEPTION 'already_used';  END IF;
  IF v_code.status = 'cancelled' THEN RAISE EXCEPTION 'cancelled';     END IF;
  IF v_code.expires_at IS NOT NULL AND v_code.expires_at < now() THEN
    RAISE EXCEPTION 'expired';
  END IF;
  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id THEN
    RAISE EXCEPTION 'not_your_code';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
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

    SELECT * INTO v_product FROM products
    WHERE id = (v_item->>'product_id')::uuid AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(trim(v_item->>'option_id'), '') = '' THEN
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

  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  -- قيمة الرمز يجب أن تساوي أو تزيد عن الإجمالي (يُحسب في القاعدة)
  IF v_code.amount < v_total THEN
    RAISE EXCEPTION 'amount_too_low';
  END IF;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id,
        transaction_reference, ocr_status, amount_verified, refunded,
        review_reason, review_severity
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'bank', 'pending_review', v_coupon_id,
        'CODE:' || v_code.code, 'needs_admin_check', true, false,
        'دفع برمز إدارة (' || v_code.code || ') بقيمة ' || v_code.amount || ' ج.س', 'normal'
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  UPDATE payment_codes
     SET status     = 'used',
         used_by    = v_user_id,
         used_at    = now(),
         order_id   = v_ids[array_length(v_ids, 1)],
         updated_at = now()
   WHERE id = v_code.id;

  RETURN QUERY SELECT unnest(v_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text) TO authenticated;
