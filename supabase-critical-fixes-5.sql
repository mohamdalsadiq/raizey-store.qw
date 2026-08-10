-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — الجزء 5: إصلاح خصم المحفظة + نظام الإيصالات الموحّد
--                        + تحصين الكوبونات وكروت الهدايا
--
-- شغّل هذا الملف بعد:
--   supabase-security.sql
--   supabase-critical-fixes-2.sql
--   supabase-critical-fixes-3.sql
--   supabase-critical-fixes-4.sql
--
-- الملف idempotent (آمن للتشغيل أكثر من مرة) ولا يحذف أي بيانات.
--
-- ═══════════════════════════════════════════════════════════════════
-- سبب وجود هذا الملف (نتيجة الفحص المباشر للكود والقاعدة):
--
-- 1) 🔴 خطأ "حصل خطأ أثناء الخصم من المحفظة" — السبب الجذري:
--    التريجر public.verify_order_price_before_insert يرفض أي إدخال
--    فيه payment_type = 'wallet' برسالة use_create_wallet_order_rpc
--    إلا إذا كانت علامة الجلسة raizey.trusted_order = 'on'.
--    النسخة الأخيرة من create_wallet_order (في fixes-3 / PART 15)
--    أُعيد إنشاؤها بدون السطر:
--        PERFORM set_config('raizey.trusted_order','on',true);
--    فصارت الدالة نفسها تُرفض بواسطة التريجر → كل عملية دفع من
--    المحفظة تفشل مهما كان الرصيد. (المبلغ لا يُخصم لأن الـ EXCEPTION
--    يُرجِع كل شيء، لكن المستخدم يرى الخطأ.)
--
-- 2) 🔴 الفهرس uq_orders_receipt_hash فريد على مستوى الصف الواحد،
--    بينما سلة فيها منتجَين تُدخل صفَّي orders بنفس بصمة الإيصال
--    ونفس رقم العملية → الطلب الثاني يفشل بخطأ duplicate key.
--    الحل: نقل شرط "عدم التكرار" إلى جدول إيصالات موحّد
--    payment_receipts (صف واحد لكل إيصال) وربط الطلبات به.
--
-- 3) 🔴 فحص التكرار كان يجري في المتصفح (SELECT ثم INSERT) وهذا
--    قابل للتجاوز والسباق الزمني. الآن التكرار يُرفض ذرّياً داخل
--    القاعدة عبر claim_payment_receipt + قيود UNIQUE حقيقية.
--
-- 4) 🔴 الكوبون كان يُستهلَك مرة لكل قطعة في السلة (حلقة على الكمية)
--    في مسار المحفظة → كوبون بحد استخدام واحد يُستهلك 3 مرات.
--    الحل: دالة واحدة للسلة كاملة تستهلك الكوبون مرة واحدة فقط
--    وتسجّله في coupon_redemptions (مرة واحدة لكل مستخدم).
--
-- 5) 🔴 وجود نسختين من validate_coupon / use_coupon_atomic
--    (بمعامل واحد وبمعاملين) يسبب غموض اختيار الدالة في PostgREST.
--    الحل: نسخة واحدة قانونية لكل دالة مع معامل افتراضي.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 0: دوال مساعدة — تطبيع رقم العملية
-- ═══════════════════════════════════════════════════════════════════
-- التطبيع يمنع خدع التكرار: "FT-2507 191234" و "ft2507191234"
-- و "FT_2507191234" كلها تُصبح نفس القيمة تماماً.
CREATE OR REPLACE FUNCTION public.normalize_tx_ref(p_ref text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT NULLIF(
    regexp_replace(upper(coalesce(p_ref, '')), '[^A-Z0-9]', '', 'g'),
    ''
  );
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: جدول الإيصالات الموحّد payment_receipts
-- ═══════════════════════════════════════════════════════════════════
-- صف واحد لكل إيصال/تحويل، سواء كان لطلب شراء أو لشحن محفظة.
-- هنا يقع حاجز "لا تكرار نهائياً" (Strict Unique) على:
--   • رقم العملية بعد التطبيع (tx_ref_norm)
--   • بصمة صورة الإيصال SHA-256 (receipt_hash)
CREATE TABLE IF NOT EXISTS public.payment_receipts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  purpose           text NOT NULL CHECK (purpose IN ('order', 'topup')),
  provider          text,                       -- bankak / ocash / fawry / other
  payment_method_id uuid,
  tx_ref_raw        text NOT NULL,              -- كما كتبه المستخدم
  tx_ref_norm       text NOT NULL,              -- بعد التطبيع (فريد)
  tx_ref_ocr        text,                       -- المُستخرج من الصورة
  receipt_hash      text NOT NULL,              -- بصمة الصورة (فريدة)
  receipt_path      text,                       -- مسار الملف في Storage
  amount_expected   numeric,
  amount_detected   numeric,
  amount_verified   boolean NOT NULL DEFAULT false,
  ref_verified      boolean NOT NULL DEFAULT false,
  ocr_status        text    NOT NULL DEFAULT 'needs_review',
  ocr_confidence    numeric,
  risk_flags        text[]  NOT NULL DEFAULT '{}',
  ocr_data          jsonb   NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_receipts_tx_norm
  ON public.payment_receipts (tx_ref_norm);

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_receipts_hash
  ON public.payment_receipts (receipt_hash);

CREATE INDEX IF NOT EXISTS idx_payment_receipts_user
  ON public.payment_receipts (user_id, created_at DESC);

ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;

-- الربط من الطلبات وطلبات الشحن إلى الإيصال
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES public.payment_receipts(id);
ALTER TABLE public.wallet_topups
  ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES public.payment_receipts(id);

CREATE INDEX IF NOT EXISTS idx_orders_receipt_id  ON public.orders(receipt_id);
CREATE INDEX IF NOT EXISTS idx_topups_receipt_id  ON public.wallet_topups(receipt_id);

-- ── إزالة القيود الفريدة القديمة التي تمنع السلة متعددة المنتجات ──
-- (التكرار الآن محكوم في payment_receipts، وهذا هو المكان الصحيح له)
DROP INDEX IF EXISTS public.uq_orders_receipt_hash;
DROP INDEX IF EXISTS public.uq_topups_receipt_hash;
DROP INDEX IF EXISTS public.uq_orders_transaction_reference;
DROP INDEX IF EXISTS public.uq_topups_transaction_reference;

-- فهارس بحث (غير فريدة) للأدمن وللفحص التاريخي
CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash
  ON public.orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash
  ON public.wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_txref_norm
  ON public.orders (public.normalize_tx_ref(transaction_reference));
CREATE INDEX IF NOT EXISTS idx_topups_txref_norm
  ON public.wallet_topups (public.normalize_tx_ref(transaction_reference));

-- ── سياسات RLS ──
DROP POLICY IF EXISTS "receipts_select_own"  ON public.payment_receipts;
DROP POLICY IF EXISTS "receipts_admin_all"   ON public.payment_receipts;
DROP POLICY IF EXISTS "receipts_no_write"    ON public.payment_receipts;

-- القراءة: صاحب الإيصال أو الأدمن
CREATE POLICY "receipts_select_own" ON public.payment_receipts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- الأدمن فقط يعدّل/يحذف. الإدخال يمر عبر claim_payment_receipt حصراً
-- (SECURITY DEFINER) فلا نمنح INSERT للعميل إطلاقاً.
CREATE POLICY "receipts_admin_all" ON public.payment_receipts
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: claim_payment_receipt — الحاجز الذرّي ضد التكرار
-- ═══════════════════════════════════════════════════════════════════
-- يُنادى مرة واحدة قبل إدخال الطلبات. إن نجح: الإيصال أصبح محجوزاً
-- باسم هذا المستخدم ولا يمكن لأي شخص (ولا هو نفسه) إعادة استخدامه.
--
-- أخطاء واضحة تُعاد للواجهة:
--   duplicate_transaction_ref  → رقم العملية مستخدم من قبل
--   duplicate_receipt_image    → نفس صورة الإيصال مستخدمة من قبل
--   invalid_receipt_input      → بيانات ناقصة
--   receipt_rejected           → الفحص الذكي رفض الإيصال
DROP FUNCTION IF EXISTS public.claim_payment_receipt(text, text, uuid, text, text, text, numeric, numeric, jsonb);

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
    v_status := 'passed';
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


-- ═══════════════════════════════════════════════════════════════════
-- PART 3: تريجر الطلبات — نسخة مصححة
-- ═══════════════════════════════════════════════════════════════════
-- إضافات هذه النسخة:
--   • طلب التحويل البنكي يجب أن يكون مربوطاً بإيصال محجوز لنفس المستخدم
--   • رقم العملية وبصمة الصورة تُنسخ من صف الإيصال (مصدر الحقيقة)
--   • حالة الفحص الذكي تُقرأ من الإيصال لا من المتصفح
CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product      RECORD;
  v_receipt      RECORD;
  v_rate         numeric;
  v_margin       numeric;
  v_expected     numeric;
  v_option_usd   numeric;
  v_discount_pct numeric := 0;
  v_min_allowed  numeric;
BEGIN
  -- مسار موثوق (دوال المحفظة) أو أدمن → السعر محسوب أصلاً بالسيرفر
  IF COALESCE(current_setting('raizey.trusted_order', true), '') = 'on'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  IF NEW.selected_option IS NOT NULL
     AND (NEW.selected_option->>'price_usd') IS NOT NULL THEN
    v_option_usd := COALESCE((NEW.selected_option->>'price_usd')::numeric, 0);
    IF v_option_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_expected := v_option_usd * v_rate * (1 + v_margin / 100.0);
  ELSE
    v_expected := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
  END IF;

  IF v_expected IS NULL OR v_expected <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF NEW.coupon_id IS NOT NULL THEN
    SELECT discount_percent INTO v_discount_pct
    FROM coupons WHERE id = NEW.coupon_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_coupon';
    END IF;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_min_allowed := v_expected * (1.0 - v_discount_pct / 100.0) * 0.99;

  IF NEW.price_sdg_snapshot IS NULL OR NEW.price_sdg_snapshot < v_min_allowed THEN
    RAISE EXCEPTION 'price_tampered';
  END IF;

  -- طلبات المحفظة تمر عبر RPC فقط
  IF NEW.payment_type = 'wallet' THEN
    RAISE EXCEPTION 'use_create_wallet_order_rpc';
  END IF;

  -- ── التحويل البنكي: لا طلب بدون إيصال محجوز ──
  IF NEW.payment_type = 'bank' THEN
    IF NEW.receipt_id IS NULL THEN
      RAISE EXCEPTION 'receipt_required';
    END IF;

    SELECT * INTO v_receipt FROM payment_receipts
    WHERE id = NEW.receipt_id AND user_id = auth.uid() AND purpose = 'order';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_not_owned';
    END IF;

    -- مصدر الحقيقة هو صف الإيصال، لا ما يرسله المتصفح
    NEW.transaction_reference := v_receipt.tx_ref_raw;
    NEW.receipt_hash          := v_receipt.receipt_hash;
    NEW.ocr_status            := v_receipt.ocr_status;
    NEW.amount_verified       := v_receipt.amount_verified;
  ELSE
    NEW.amount_verified := false;
  END IF;

  -- إجبار الحالة الآمنة: العميل لا يعيّن حالة الطلب
  NEW.status   := 'pending_review';
  NEW.refunded := false;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_verify_order_price ON public.orders;
CREATE TRIGGER trg_verify_order_price
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.verify_order_price_before_insert();


-- ═══════════════════════════════════════════════════════════════════
-- PART 4: الكوبونات — نسخة واحدة قانونية لكل دالة
-- ═══════════════════════════════════════════════════════════════════
-- إزالة كل النسخ المتعددة التي تسبب غموض الاختيار في PostgREST
DROP FUNCTION IF EXISTS public.validate_coupon(text);
DROP FUNCTION IF EXISTS public.validate_coupon(text, numeric);
DROP FUNCTION IF EXISTS public.use_coupon_atomic(text);
DROP FUNCTION IF EXISTS public.use_coupon_atomic(text, numeric);

-- فحص الكوبون للعرض فقط (لا يغيّر أي شيء)
-- يتحقق أيضاً: هل استهلكه هذا المستخدم من قبل؟ وهل يحقق الحد الأدنى؟
CREATE OR REPLACE FUNCTION public.validate_coupon(
  p_code        text,
  p_order_total numeric DEFAULT NULL
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT c.id, c.discount_percent, COALESCE(c.min_order_sdg, 0) AS min_order_sdg
  INTO v_coupon
  FROM coupons c
  WHERE upper(c.code) = upper(trim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'coupon_already_used';
  END IF;

  IF p_order_total IS NOT NULL AND v_coupon.min_order_sdg > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  RETURN QUERY SELECT v_coupon.id, LEAST(GREATEST(v_coupon.discount_percent, 0), 95);
END;
$$;

-- استهلاك الكوبون ذرّياً — مرة واحدة لكل مستخدم
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(
  p_code        text,
  p_order_total numeric DEFAULT NULL
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
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

  SELECT * INTO v_coupon FROM coupons
  WHERE upper(code) = upper(trim(p_code))
    AND is_active = true
    AND (max_uses   IS NULL OR COALESCE(uses_count, 0) < max_uses)
    AND (expires_at IS NULL OR expires_at > now())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF p_order_total IS NOT NULL AND COALESCE(v_coupon.min_order_sdg, 0) > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  -- القيد UNIQUE(coupon_id, user_id) هو الحاجز الحقيقي ضد التكرار
  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id) VALUES (v_coupon.id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'coupon_already_used';
  END;

  UPDATE coupons SET uses_count = COALESCE(uses_count, 0) + 1
  WHERE id = v_coupon.id;

  v_pct := LEAST(GREATEST(COALESCE(v_coupon.discount_percent, 0), 0), 95);
  RETURN QUERY SELECT v_coupon.id, v_pct;
END;
$$;

-- سياسات coupon_redemptions: قراءة لصاحبها، والكتابة عبر الدوال فقط
DROP POLICY IF EXISTS "coupon_redemptions_select_own" ON public.coupon_redemptions;
DROP POLICY IF EXISTS "coupon_redemptions_admin"      ON public.coupon_redemptions;
CREATE POLICY "coupon_redemptions_select_own" ON public.coupon_redemptions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY "coupon_redemptions_admin" ON public.coupon_redemptions
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 5: 🔴 الإصلاح الأساسي — create_wallet_order مع العلامة الموثوقة
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);
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

  IF EXISTS (SELECT 1 FROM store_settings WHERE maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
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

  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

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

    v_option_price_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_price_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
  ELSE
    v_price_sdg     := v_product.price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_price_sdg) uc;
    v_price_sdg := v_price_sdg * (1.0 - COALESCE(v_discount_pct, 0) / 100.0);
  END IF;

  v_price_sdg := ROUND(v_price_sdg);
  IF v_price_sdg <= 0 THEN
    v_price_sdg := 1;
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets SET balance = balance - v_price_sdg, updated_at = now()
  WHERE user_id = v_user_id;

  -- 🔴🔴 السطر المفقود الذي كان يُفشل كل عمليات الدفع من المحفظة 🔴🔴
  PERFORM set_config('raizey.trusted_order', 'on', true);

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id
  ) VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'::jsonb),
    COALESCE(p_field_labels, '{}'::jsonb), v_option,
    'wallet', 'in_progress', v_coupon_id
  )
  RETURNING orders.id INTO v_order_id;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT v_order_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 6: create_wallet_orders_bulk — السلة كاملة في معاملة واحدة
-- ═══════════════════════════════════════════════════════════════════
-- p_items مثال:
-- [{"product_id":"...","option_id":"opt_x","quantity":3,
--   "field_values":{...},"field_labels":{...}}]
--
-- المزايا مقابل النداء المتكرر لـ create_wallet_order:
--   • الكوبون يُستهلك مرة واحدة للسلة كاملة (لا مرة لكل قطعة)
--   • خصم واحد من المحفظة بإجمالي السلة، أو لا شيء إطلاقاً (ذرّية)
--   • لا تبقى طلبات نصف منفّذة إذا فشلت القطعة الأخيرة
DROP FUNCTION IF EXISTS public.create_wallet_orders_bulk(jsonb, text);

CREATE OR REPLACE FUNCTION public.create_wallet_orders_bulk(
  p_items       jsonb,
  p_coupon_code text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       uuid := auth.uid();
  v_rate          numeric;
  v_margin        numeric;
  v_balance       numeric;
  v_coupon_id     uuid;
  v_discount_pct  numeric := 0;
  v_total         numeric := 0;
  v_item          jsonb;
  v_product       RECORD;
  v_option        jsonb;
  v_option_usd    numeric;
  v_unit          numeric;
  v_qty           int;
  v_name          text;
  v_order_id      uuid;
  v_lines         jsonb := '[]'::jsonb;
  v_line          jsonb;
  v_ids           uuid[] := '{}';
  i               int;
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

  -- ── الكوبون: مرة واحدة فقط للسلة كاملة ──
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

  -- ── خصم واحد ذرّي بإجمالي السلة ──
  SELECT balance INTO v_balance FROM wallets WHERE user_id = v_user_id FOR UPDATE;
  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_balance < v_total THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets SET balance = balance - v_total, updated_at = now()
  WHERE user_id = v_user_id;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  -- ── المرور الثاني: إدخال الطلبات (صف لكل قطعة) ──
  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'wallet', 'in_progress', v_coupon_id
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
-- PART 7: كروت الهدايا — تحصين إضافي (انتهاء الصلاحية + سجل)
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.redeem_gift_card(text);

CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
RETURNS TABLE(amount numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card    RECORD;
  v_user_id uuid := auth.uid();
  v_updated uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF public.normalize_tx_ref(p_code) IS NULL THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  SELECT * INTO v_card FROM gift_cards
  WHERE upper(code) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_card.is_redeemed, false) = true THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  IF v_card.expires_at IS NOT NULL AND v_card.expires_at <= now() THEN
    RAISE EXCEPTION 'giftcard_expired';
  END IF;

  IF COALESCE(v_card.amount, 0) <= 0 THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  -- التحديث الشرطي هو الحاجز ضد الاستبدال المزدوج المتزامن
  UPDATE gift_cards
  SET is_redeemed = true, redeemed_by = v_user_id, redeemed_at = now()
  WHERE id = v_card.id AND COALESCE(is_redeemed, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  INSERT INTO wallets (user_id, balance)
  VALUES (v_user_id, v_card.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_card.amount, updated_at = now();

  RETURN QUERY SELECT v_card.amount;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 8: الصلاحيات — anon لا ينفّذ أي دالة مالية
-- ═══════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.claim_payment_receipt(text, text, text, text, text, uuid, numeric, numeric, text, text, numeric, text[], jsonb) FROM anon, public;
REVOKE ALL ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text)  FROM anon, public;
REVOKE ALL ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)               FROM anon, public;
REVOKE ALL ON FUNCTION public.validate_coupon(text, numeric)                       FROM anon, public;
REVOKE ALL ON FUNCTION public.use_coupon_atomic(text, numeric)                     FROM anon, public;
REVOKE ALL ON FUNCTION public.redeem_gift_card(text)                               FROM anon, public;

GRANT EXECUTE ON FUNCTION public.claim_payment_receipt(text, text, text, text, text, uuid, numeric, numeric, text, text, numeric, text[], jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_coupon(text, numeric)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(text, numeric)                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_gift_card(text)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_tx_ref(text)                               TO authenticated, anon;

GRANT SELECT ON public.payment_receipts TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- PART 9: تحقق نهائي — يطبع النتيجة في محرر SQL
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT prosrc LIKE '%raizey.trusted_order%'
  INTO v_ok
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'create_wallet_order'
  LIMIT 1;

  IF COALESCE(v_ok, false) THEN
    RAISE NOTICE '✅ create_wallet_order يحتوي العلامة الموثوقة — الدفع من المحفظة يعمل الآن';
  ELSE
    RAISE WARNING '❌ العلامة الموثوقة غير موجودة — راجع PART 5';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'payment_receipts') THEN
    RAISE NOTICE '✅ جدول payment_receipts جاهز';
  END IF;
END $$;
