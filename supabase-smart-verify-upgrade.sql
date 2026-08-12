-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — ترقية "الفحص الذكي للإيصالات"
-- ملف: supabase-smart-verify-upgrade.sql
--
-- شغّل هذا الملف في: Supabase → SQL Editor
-- يُشغَّل بعد الملفات السابقة (خصوصاً supabase-critical-fixes-5.sql).
--
-- الملف idempotent (آمن للتشغيل أكثر من مرة) ولا يحذف أي بيانات.
--
-- سبب وجوده (نتيجة فحص الكود المباشر):
--   الواجهة (checkout.html / receipt.html / my-orders.html /
--   admin-orders.html) تستدعي فعلياً:
--     • العمود  orders.order_code            (رقم طلب مختصر للعميل)
--     • الدالة  log_receipt_fraud_attempt()  (تسجيل محاولات الاحتيال)
--   لكن أياً منهما لم يُنشأ في قاعدة البيانات بعد، فكانت:
--     • أرقام الطلبات تظهر كـ UUID طويل (fallback: order_code || id)
--     • تسجيل محاولات الاحتيال يفشل صامتاً (مغلّف بـ try/catch)
--   هذا الملف يُنشئ الجزء الناقص في القاعدة ليكتمل النظام.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: رقم طلب مختصر order_code (5–6 خانات) — بديل عرض عن الـ UUID
-- ═══════════════════════════════════════════════════════════════════
-- الـ id (UUID) يبقى كما هو داخلياً دون كسر أي علاقات؛ order_code
-- مجرد رمز عرض/بحث قصير للعميل والأدمن.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_code text;

-- فهرس فريد: NULL مسموح به (للطلبات القديمة قبل الـ backfill)،
-- والقيم غير الفارغة يجب أن تكون فريدة تماماً.
CREATE UNIQUE INDEX IF NOT EXISTS orders_order_code_key
  ON public.orders(order_code);

-- تسلسل احتياطي مضمون التفرّد يُستخدم فقط إذا فشل العشوائي في إيجاد رمز حر
CREATE SEQUENCE IF NOT EXISTS public.order_code_seq START 100000;

-- توليد رمز فريد 6 خانات مع loop لتفادي التصادم.
-- SECURITY DEFINER مهم: فحص التفرّد يجب أن يرى كل الصفوف متجاوزاً RLS،
-- وإلا رأى المستخدم صفوفه فقط وظنّ الرمز حراً بينما هو مستخدم لغيره.
CREATE OR REPLACE FUNCTION public.gen_order_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_try  int := 0;
BEGIN
  LOOP
    v_try := v_try + 1;
    -- رقم عشوائي من 6 خانات: 100000..999999
    v_code := lpad(((floor(random() * 900000))::int + 100000)::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.orders WHERE order_code = v_code);

    -- بعد 25 محاولة فاشلة (نادر جداً) → رمز مضمون من التسلسل
    IF v_try >= 25 THEN
      v_code := nextval('public.order_code_seq')::text;
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.orders WHERE order_code = v_code);
    END IF;
  END LOOP;
  RETURN v_code;
END;
$$;

-- تريجر BEFORE INSERT: يملأ order_code تلقائياً إن كان فارغاً.
-- منفصل عن trg_verify_order_price حتى لا يتعارض معه.
CREATE OR REPLACE FUNCTION public.set_order_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.order_code IS NULL OR btrim(NEW.order_code) = '' THEN
    NEW.order_code := public.gen_order_code();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_order_code ON public.orders;
CREATE TRIGGER trg_set_order_code
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_order_code();

-- Backfill: منح كل الطلبات القديمة رمزاً مختصراً
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.orders WHERE order_code IS NULL LOOP
    UPDATE public.orders
      SET order_code = public.gen_order_code()
      WHERE id = r.id;
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: تسجيل محاولات الاحتيال receipt_fraud_attempts
-- ═══════════════════════════════════════════════════════════════════
-- كل محاولة مرفوضة/مكررة/فاشلة تُسجَّل هنا لرصد الأنماط المشبوهة
-- (محاولات متكررة بأرقام عشوائية = مؤشر تحايل).
CREATE TABLE IF NOT EXISTS public.receipt_fraud_attempts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at          timestamptz NOT NULL DEFAULT now(),
  user_id             uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  entered_reference   text,          -- رقم العملية كما أدخله العميل
  normalized_reference text,         -- بعد التطبيع (للمقارنة/الرصد)
  reason              text,          -- duplicate / no_reference / not_a_receipt / amount_mismatch / technical_failure ...
  provider            text,          -- fawry / ocash / bankak / cash / unknown
  ocr_excerpt         text,          -- مقتطف من نص OCR للتشخيص
  order_amount        numeric,
  metadata            jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_fraud_attempts_user
  ON public.receipt_fraud_attempts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fraud_attempts_norm
  ON public.receipt_fraud_attempts (normalized_reference);
CREATE INDEX IF NOT EXISTS idx_fraud_attempts_created
  ON public.receipt_fraud_attempts (created_at DESC);

ALTER TABLE public.receipt_fraud_attempts ENABLE ROW LEVEL SECURITY;

-- لا إدخال مباشر من العميل: الإدخال يمر حصراً عبر RPC (SECURITY DEFINER).
-- القراءة للأدمن فقط.
DROP POLICY IF EXISTS "fraud_attempts_admin_select" ON public.receipt_fraud_attempts;
DROP POLICY IF EXISTS "fraud_attempts_admin_all"    ON public.receipt_fraud_attempts;

CREATE POLICY "fraud_attempts_admin_all" ON public.receipt_fraud_attempts
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 3: RPC آمنة لتسجيل المحاولة — تطابق استدعاء الواجهة تماماً
-- ═══════════════════════════════════════════════════════════════════
-- تُستدعى من checkout.html بالمعاملات المسمّاة:
--   p_entered_reference, p_reason, p_provider,
--   p_ocr_excerpt, p_order_amount, p_metadata
-- SECURITY DEFINER: تُدخل الصف رغم أن العميل لا يملك INSERT مباشراً.
DROP FUNCTION IF EXISTS public.log_receipt_fraud_attempt(text, text, text, text, numeric, jsonb);

CREATE OR REPLACE FUNCTION public.log_receipt_fraud_attempt(
  p_entered_reference text,
  p_reason            text,
  p_provider          text    DEFAULT NULL,
  p_ocr_excerpt       text    DEFAULT NULL,
  p_order_amount      numeric DEFAULT NULL,
  p_metadata          jsonb   DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_id      uuid;
BEGIN
  -- التسجيل ثانوي: لا نرمي خطأً يعطّل تدفق الدفع عند العميل.
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.receipt_fraud_attempts (
    user_id, entered_reference, normalized_reference,
    reason, provider, ocr_excerpt, order_amount, metadata
  ) VALUES (
    v_user_id,
    NULLIF(btrim(coalesce(p_entered_reference, '')), ''),
    public.normalize_tx_ref(p_entered_reference),
    NULLIF(btrim(coalesce(p_reason, '')), ''),
    NULLIF(btrim(coalesce(p_provider, '')), ''),
    left(coalesce(p_ocr_excerpt, ''), 500),
    p_order_amount,
    coalesce(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  -- أي فشل في التسجيل لا يجوز أن يكسر عملية الدفع
  RETURN NULL;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 4: الصلاحيات
-- ═══════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.log_receipt_fraud_attempt(text, text, text, text, numeric, jsonb) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.log_receipt_fraud_attempt(text, text, text, text, numeric, jsonb) TO authenticated;

-- gen_order_code / set_order_code تعملان داخل التريجر فقط؛ لا حاجة لمنح
-- تنفيذها للعميل. نمنعها احتياطاً عن anon/public.
REVOKE ALL ON FUNCTION public.gen_order_code()  FROM anon, public;
REVOKE ALL ON FUNCTION public.set_order_code()  FROM anon, public;


-- ═══════════════════════════════════════════════════════════════════
-- تم. النتيجة:
--   ✅ كل طلب (قديم وجديد) يملك order_code مختصر فريد.
--   ✅ الواجهة تعرض order_code بدل الـ UUID تلقائياً.
--   ✅ الأدمن يبحث بالكود (البحث في admin-orders.html يشمله أصلاً).
--   ✅ محاولات الاحتيال (تكرار/رفض/فشل) تُسجَّل فعلياً في القاعدة.
--   ✅ لا إدخال مباشر لجدول الاحتيال — عبر RPC آمنة فقط، والقراءة للأدمن.
-- ═══════════════════════════════════════════════════════════════════
