-- ============================================================================
-- MEEM STORE — المرحلة 1: نطاق أوراكل الإيصالات + قوة كود الكوبون + طول كود الدفع
-- File    : db/migrations/2026-10-13_p1_oracle_scope_and_coupon_strength.sql
-- Scope   : كائنات القاعدة فقط — لا يُلمَس أي صف بيانات زبون.
-- Apply   : داخل معاملة واحدة (BEGIN … COMMIT) بعد ملفات 2026-10-08.
-- Rollback: db/rollback/2026-10-13_p1_oracle_scope_and_coupon_strength_rollback.sql
--
-- السياق: بقية بنود M3/M4/M6 من تقرير التدقيق.
--   • حد المعدل الموحّد (public.consume_chat_rate_limit) مطبَّق أصلًا على
--     validate_coupon / validate_payment_code / report_fraud_alert /
--     log_receipt_fraud_attempt في db/migrations/2026-10-08_security_hardening.sql.
--     هذا الملف يضيف المسار الناقص (check_tx_ref_available) ويرفع طول أكواد
--     الدفع إلى 10 كي تكتمل مجموعة الدوال الخمس بنفس العقد.
--   • H1/M3: check_tx_ref_available كان يفحص صفوف كل المستخدمين عالميًا
--     (أوراكل تعداد أرقام عمليات الآخرين). صار يفحص صفوف المستخدم نفسه فقط
--     فوق حد معدل موحّد.
--   • M6: أي كوبون جديد (أو تغيير كود قائم) يجب أن يكون 10 خانات
--     أبجدية-رقمية على الأقل. الصفوف القديمة لا تُمسّ إطلاقًا.
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════════
-- 1) check_tx_ref_available — نطاق المستخدم نفسه فقط + حد معدل موحّد
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
RETURNS TABLE(available boolean, reason text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_norm    text;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  -- حد معدل موحّد: يمنع استخدام الدالة كأداة تعداد مكثّفة
  SELECT * INTO v_rate
  FROM public.consume_chat_rate_limit('txref:' || v_user_id::text, 30, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text;
    RETURN;
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RETURN QUERY SELECT false, 'invalid_tx_ref'::text;
    RETURN;
  END IF;

  -- نطاق الفحص: صفوف المستخدم نفسه فقط.
  -- الحماية الحقيقية من إعادة استخدام أرقام الآخرين تبقى قيدًا فريدًا على القاعدة.
  IF EXISTS (
       SELECT 1 FROM public.payment_receipts r
       WHERE r.tx_ref_norm = v_norm AND r.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.orders o
       WHERE public.normalize_tx_ref(o.transaction_reference) = v_norm
         AND o.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.wallet_topups t
       WHERE public.normalize_tx_ref(t.transaction_reference) = v_norm
         AND t.user_id = v_user_id
     ) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'available'::text;
END
$fn$;
REVOKE EXECUTE ON FUNCTION public.check_tx_ref_available(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 2) validate_payment_code — رفع حد الطول الأدنى من 4 إلى 10
--    (كل الأكواد الحالية 13 خانة بصيغة RZY-XXXX-XXXX، فلا يوجد كسر)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_code    RECORD;
  v_norm    text;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('paycode:' || v_user_id::text, 60, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  v_norm := upper(btrim(coalesce(p_code, '')));
  -- أكواد الدفع 13 خانة (RZY-XXXX-XXXX)؛ أي مدخل أقصر مرفوض قبل أي بحث
  IF length(v_norm) < 10 THEN
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
END
$fn$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3) M6 — الكوبونات الجديدة 10 خانات أبجدية-رقمية على الأقل
--    تريجر يتحقق عند الإدراج أو عند تغيير الكود فقط — الصفوف القديمة لا تُمسّ.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.enforce_coupon_code_strength()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code THEN
    IF length(regexp_replace(coalesce(NEW.code, ''), '[^A-Za-z0-9]', '', 'g')) < 10 THEN
      RAISE EXCEPTION 'coupon_code_too_short: at least 10 alphanumeric characters required';
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;
REVOKE EXECUTE ON FUNCTION public.enforce_coupon_code_strength() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_enforce_coupon_code_strength ON public.coupons;
CREATE TRIGGER trg_enforce_coupon_code_strength
  BEFORE INSERT OR UPDATE OF code ON public.coupons
  FOR EACH ROW EXECUTE FUNCTION public.enforce_coupon_code_strength();

-- ════════════════════════════════════════════════════════════════════════════
-- 4) فحص ذاتي: يجب أن تظهر الدوال والصفوف كما هو متوقّع
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'check_tx_ref_available' LIMIT 1;
  IF v_src IS NULL OR position('consume_chat_rate_limit' in v_src) = 0
     OR position('r.user_id = v_user_id' in v_src) = 0 THEN
    RAISE EXCEPTION 'p1_apply_check_failed: check_tx_ref_available';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND c.relname = 'coupons'
      AND t.tgname = 'trg_enforce_coupon_code_strength'
  ) THEN
    RAISE EXCEPTION 'p1_apply_check_failed: coupon strength trigger missing';
  END IF;
END $$;
