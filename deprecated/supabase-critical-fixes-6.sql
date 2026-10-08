-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — الجزء 6: الطلب البنكي في معاملة واحدة ذرّية
--                        + فحص توفّر رقم العملية قبل الإرسال
--
-- شغّل هذا الملف بعد supabase-critical-fixes-5.sql
-- الملف idempotent (آمن للتشغيل أكثر من مرة) ولا يحذف أي بيانات.
--
-- ═══════════════════════════════════════════════════════════════════
-- سبب وجود هذا الملف:
--
-- 1) 🔴 رقم العملية كان "يُقفل" حتى لو لم يكتمل الطلب.
--    السبب: المتصفح كان ينفّذ خطوتين منفصلتين تماماً:
--      (أ) claim_payment_receipt  → يعمل COMMIT فوراً ويحجز tx_ref_norm
--      (ب) insert into orders     → استدعاء منفصل بعده
--    فإذا فشلت (ب) لأي سبب (كوبون، شبكة، إلغاء، إغلاق الصفحة) يبقى رقم
--    العملية محجوزاً للأبد بينما لا يوجد أي طلب فعلي — فيرى العميل
--    "رقم العملية هذا تم استخدامه من قبل" وهو لم يُكمل أي طلب.
--
--    الحل: create_bank_orders_bulk — دالة واحدة تفعل كل شيء داخل معاملة
--    واحدة: حجز الإيصال + استهلاك الكوبون + إدخال كل صفوف الطلب.
--    إما ينجح الكل، أو يرجع الكل (ROLLBACK) ويبقى رقم العملية متاحاً.
--
-- 2) 🟠 تجربة استخدام أفضل: check_tx_ref_available للقراءة فقط (بلا حجز)
--    ليعرف العميل مبكراً أن الرقم مستخدم قبل أن يرفع الصورة ويحوّل.
--    ملاحظة أمنية: هذه الدالة **لا تحجز** شيئاً، والحجز الحقيقي يبقى
--    ذرّياً داخل create_bank_orders_bulk (فلا سباق زمني ولا تلاعب).
--
-- 3) 🟠 orders.receipt_url لم يكن يُملأ في مسار الشراء البنكي بعد
--    توحيد الإيصالات، فكان الأدمن لا يرى صورة الإيصال. الآن الدالة
--    تكتب الرابط الموقّع (Signed URL) في الطلب وفي صف الإيصال.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: check_tx_ref_available — فحص توفّر رقم العملية (قراءة فقط)
-- ═══════════════════════════════════════════════════════════════════
-- ترجع available = false إذا كان الرقم مستخدماً في:
--   • جدول الإيصالات الموحّد payment_receipts
--   • أو سجلات قديمة في orders / wallet_topups
DROP FUNCTION IF EXISTS public.check_tx_ref_available(text);

CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
RETURNS TABLE(available boolean, reason text)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_norm    text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);

  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RETURN QUERY SELECT false, 'invalid_tx_ref';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM payment_receipts WHERE tx_ref_norm = v_norm) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) OR EXISTS (
    SELECT 1 FROM wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref';
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'available';
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: create_bank_orders_bulk — الطلب البنكي كاملاً في معاملة واحدة
-- ═══════════════════════════════════════════════════════════════════
-- p_items:
--   [{"product_id":"...","option_id":"opt_x","quantity":2,
--     "field_values":{...},"field_labels":{...}}]
--
-- p_receipt:
--   {"tx_ref":"...", "receipt_hash":"<sha256 hex>", "receipt_path":"...",
--    "receipt_url":"...", "provider":"bankak", "payment_method_id":"<uuid>",
--    "amount_detected":50000, "tx_ref_ocr":"...", "ocr_status":"needs_review",
--    "ocr_confidence":90, "risk_flags":["..."], "ocr_data":{...}}
--
-- ضمانات هذه الدالة:
--   • الأسعار تُحسب من القاعدة فقط (لا يمكن التلاعب بها من المتصفح)
--   • الكوبون يُستهلك مرة واحدة للسلة كاملة
--   • حجز رقم العملية/بصمة الصورة يحدث في نفس المعاملة مع إدخال الطلبات:
--     أي فشل ⇒ ROLLBACK كامل ⇒ رقم العملية يبقى متاحاً للمحاولة مجدداً
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

  v_method_id   := NULLIF(p_receipt->>'payment_method_id', '')::uuid;
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
        v_tx_ref_raw, v_claim.ocr_status, v_claim.amount_verified, false
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
-- PART 3: الصلاحيات
-- ═══════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) FROM anon, public;
REVOKE ALL ON FUNCTION public.check_tx_ref_available(text)                FROM anon, public;

GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text)                TO authenticated;
