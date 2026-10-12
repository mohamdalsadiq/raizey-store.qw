-- ============================================================================
-- MEEM STORE (raizey-store.qw) — إغلاق بنود التدقيق المتبقية
-- File    : db/migrations/2026-10-11_hardening_remaining.sql
-- Author  : freebuff hardening session 2026-10-11 (live DB rglbfizqolrenwfsndyv)
-- Scope   : كائنات القاعدة فقط — لا حذف/تعديل أي صف بيانات زبون.
-- Notes   : يُطبَّق مرة واحدة داخل معاملة واحدة (BEGIN … COMMIT).
--           الرجوع: db/rollback/2026-10-11_hardening_remaining.sql
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════════
-- 1) M1 — إغلاق تسريب pg_stat_statements الاستطلاعي (anon/authenticated كانا
--    يقرآن خريطة القاعدة كاملة: 582 صفاً و555 منها لأدوار أخرى)
-- ════════════════════════════════════════════════════════════════════════════
REVOKE ALL ON TABLE extensions.pg_stat_statements FROM PUBLIC;
REVOKE ALL ON TABLE extensions.pg_stat_statements FROM anon;
REVOKE ALL ON TABLE extensions.pg_stat_statements FROM authenticated;
DO $$
BEGIN
  BEGIN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements(boolean) FROM PUBLIC, anon, authenticated';
  EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements() FROM PUBLIC, anon, authenticated';
  EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements_info() FROM PUBLIC, anon, authenticated';
  EXCEPTION WHEN undefined_function THEN NULL; END;
END $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 2) L1/L3 — سحب EXECUTE عن الدوال الداخلية من أدوار العملاء
--    (دوال محفزات، مساعدات، دوال اختبار داخلية — لا يستدعيها المتصفح)
-- ════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  r record;
  v_names text[] := ARRAY[
    'verify_privilege_model', 'normalize_tx_ref', 'generate_order_code',
    'set_order_code', 'touch_subcategories_updated_at', 'set_row_updated_at',
    'set_store_sections_updated_at', 'rls_auto_enable', 'bootstrap_super_admin',
    'handle_new_user', 'apply_referral_signup_metadata', 'assert_wallet_ledger_entry',
    'verify_order_price_before_insert', 'link_order_payment_code', 'award_loyalty_points',
    'protect_notification_fields', 'protect_order_fields', 'protect_profile_columns',
    'protect_profile_fields', 'protect_profile_insert', 'protect_topup_insert',
    'derive_receipt_url_from_receipt', 'validate_receipt_path',
    'enforce_coupon_code_strength', 'guard_admin_order_writes'
  ];
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY (v_names)
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.oid::regprocedure);
  END LOOP;
END $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3) لا منح EXECUTE تلقائي لأي دالة جديدة (سياسة افتراضية جديدة)
--    كل RPC جديد يوجّه للعميل يجب أن يُمنح صراحةً: GRANT ... TO authenticated
-- ════════════════════════════════════════════════════════════════════════════
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 4) H1/M3 — check_tx_ref_available: نطاق المستخدم نفسه فقط + حد معدل
--    (كان يفحص كل الصفوف عالمياً = أوراكل تعداد أرقام عمليات الآخرين)
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
  -- الحماية الحقيقية من إعادة استخدام أرقام الآخرين تبقى قيداً فريداً على القاعدة.
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
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5) M6 — رفض أكواد الدفع القصيرة كمدخل صالح (كل الأكواد الحالية 13 خانة)
--    + رفع حد الطول الأدنى في validate_payment_code من 4 إلى 10
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
-- 6) M6 — الكوبونات الجديدة 10 خانات أبجدية-رقمية على الأقل
--    (تريجر يتحقق عند الإدراج أو عند تغيير الكود فقط — الصفوف القديمة لا تُمس)
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
DROP TRIGGER IF EXISTS trg_enforce_coupon_code_strength ON public.coupons;
CREATE TRIGGER trg_enforce_coupon_code_strength
  BEFORE INSERT OR UPDATE OF code ON public.coupons
  FOR EACH ROW EXECUTE FUNCTION public.enforce_coupon_code_strength();

-- ════════════════════════════════════════════════════════════════════════════
-- 7) H4 — إزالة وصول anon إلى validate_referral_short_code
--    (كانت أوراكل تعداد للزوار: 4096 احتمالاً؛ الأكواد صارت 8 خانات والتحقق
--     الفعلي يتم خادمياً عند التسجيل عبر apply_referral_signup_metadata)
-- ════════════════════════════════════════════════════════════════════════════
REVOKE EXECUTE ON FUNCTION public.validate_referral_short_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 8) حراسة الحقول الحساسة في سياسة profiles_update_own (WITH CHECK)
--    دفاع بالعمق فوق التريجرات القائمة.
--    ⚠️ ملاحظة تقنية مهمة: كتابة استعلام على public.profiles داخل WITH CHECK
--    مباشرةً تُنتج "infinite recursion detected in policy" لكل تحديث (حتى للأدمن)،
--    لذلك المقارنة تتم عبر دالة SECURITY DEFINER (تنفَّذ كمالك الجدول، بلا RLS، بلا تكرار).
CREATE OR REPLACE FUNCTION public.profile_guard_fields_unchanged(
  p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid,
  p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean,
  p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean,
  p_loyalty_points integer
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT (p_id = auth.uid()) AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role                    IS NOT DISTINCT FROM p_role
      AND p.is_banned               IS NOT DISTINCT FROM p_is_banned
      AND p.referred_by             IS NOT DISTINCT FROM p_referred_by
      AND p.referral_code           IS NOT DISTINCT FROM p_referral_code
      AND p.referral_short_code     IS NOT DISTINCT FROM p_referral_short_code
      AND p.referral_rewarded       IS NOT DISTINCT FROM p_referral_rewarded
      AND p.referral_discount_used  IS NOT DISTINCT FROM p_referral_discount_used
      AND p.milestone10_paid        IS NOT DISTINCT FROM p_milestone10_paid
      AND p.milestone25_paid        IS NOT DISTINCT FROM p_milestone25_paid
      AND p.loyalty_points          IS NOT DISTINCT FROM p_loyalty_points
  );
$fn$;

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (
    public.profile_guard_fields_unchanged(
      id, role, is_banned, referred_by, referral_code, referral_short_code,
      referral_rewarded, referral_discount_used, milestone10_paid, milestone25_paid, loyalty_points
    )
  );
GRANT EXECUTE ON FUNCTION public.profile_guard_fields_unchanged(uuid,text,boolean,uuid,text,text,boolean,boolean,boolean,boolean,integer) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 9) receipt_url القادم من العميل: يُتجاهل تماماً ويُشتق خادمياً من الإيصال
--    - تريجر يتحقق أن receipt_path داخل مجلد صاحبه (bucket receipts خاص)
--    - تريجران يكتبان receipt_url دائماً من payment_receipts.receipt_path
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.validate_receipt_path()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.receipt_path IS NOT NULL AND btrim(NEW.receipt_path) <> '' THEN
    IF NEW.receipt_path !~ ('^' || NEW.user_id::text || '/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$') THEN
      RAISE EXCEPTION 'receipt_path_not_owned: path must live under the owner folder (%)', NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS trg_validate_receipt_path ON public.payment_receipts;
CREATE TRIGGER trg_validate_receipt_path
  BEFORE INSERT OR UPDATE OF receipt_path, user_id ON public.payment_receipts
  FOR EACH ROW EXECUTE FUNCTION public.validate_receipt_path();

CREATE OR REPLACE FUNCTION public.derive_receipt_url_from_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_path text;
BEGIN
  -- بلا إيصال موثّق ⇒ لا رابط إطلاقاً (حتى لو أرسل العميل رابطاً)
  IF NEW.receipt_id IS NULL THEN
    NEW.receipt_url := NULL;
    RETURN NEW;
  END IF;

  SELECT r.receipt_path INTO v_path
  FROM public.payment_receipts r
  WHERE r.id = NEW.receipt_id;

  -- المرجع القانوني: مسار داخلي في bucket receipts، والواجهة تولّد الرابط الموقّع
  NEW.receipt_url := CASE
    WHEN v_path IS NULL OR btrim(v_path) = '' THEN NULL
    ELSE 'receipts/' || v_path
  END;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS trg_derive_receipt_url_orders ON public.orders;
CREATE TRIGGER trg_derive_receipt_url_orders
  BEFORE INSERT OR UPDATE OF receipt_id, receipt_url ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.derive_receipt_url_from_receipt();
DROP TRIGGER IF EXISTS trg_derive_receipt_url_topups ON public.wallet_topups;
CREATE TRIGGER trg_derive_receipt_url_topups
  BEFORE INSERT OR UPDATE OF receipt_id, receipt_url ON public.wallet_topups
  FOR EACH ROW EXECUTE FUNCTION public.derive_receipt_url_from_receipt();

-- ════════════════════════════════════════════════════════════════════════════
-- 10) إعداد جديد: auto_accept_max_sdg — فوقه يتحول الإيصال لتدقيق إداري
--     0 = مطفأ (السلوك الحالي محفوظ افتراضياً). يُدار من admin-settings.
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.settings (key, value)
VALUES ('auto_accept_max_sdg', '0')
ON CONFLICT (key) DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- 11) verify_privilege_model: تغطية الفحوص الجديدة
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.verify_privilege_model()
RETURNS TABLE(check_name text, passed boolean, details text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  RETURN QUERY SELECT 'is_admin_single_banned'::text,
    (SELECT count(*) = 1 AND bool_and(p.prosrc LIKE '%is_banned%')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_admin'),
    'is_admin must be exactly one definition and enforce the banned check'::text;

  RETURN QUERY SELECT 'is_super_admin_single_banned'::text,
    (SELECT count(*) = 1 AND bool_and(p.prosrc LIKE '%is_banned%')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_super_admin'),
    'is_super_admin must be exactly one definition and enforce the banned check'::text;

  RETURN QUERY SELECT 'no_anon_grants_except_settings_ro'::text,
    (SELECT NOT EXISTS (
       SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relname IN ('profiles','audit_logs','wallet_topups','wallets','wallet_transactions',
                           'payment_receipts','receipt_scan_results','coupons','gift_cards',
                           'admin_permissions','orders','coupon_redemptions')
         AND c.relacl::text LIKE '%anon=%')
     AND (SELECT c.relacl::text ~ 'anon=r/' AND c.relacl::text !~ 'anon=[^,}]*[wWdD]'
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'settings')),
    'anon must have no grants on sensitive tables; settings anon grant must stay read-only'::text;

  RETURN QUERY SELECT 'no_open_policies'::text,
    (SELECT NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename IN ('profiles','audit_logs','wallet_topups','wallets','wallet_transactions',
                           'payment_receipts','receipt_scan_results','coupons','gift_cards',
                           'settings','admin_permissions','orders','coupon_redemptions')
         AND (qual = 'true' OR with_check = 'true'))),
    'no permissive USING(true) policies on sensitive tables'::text;

  -- (جديد) لا EXECUTE لـ anon على validate_referral_short_code
  RETURN QUERY SELECT 'anon_referral_oracle_revoked'::text,
    NOT has_function_privilege('anon', 'public.validate_referral_short_code(text)', 'EXECUTE'),
    'anon must not be able to enumerate referral codes'::text;

  -- (جديد) pg_stat_statements مغلق أمام أدوار العملاء + PUBLIC
  RETURN QUERY SELECT 'pg_stat_statements_locked'::text,
    (NOT has_table_privilege('anon', 'extensions.pg_stat_statements', 'SELECT')
     AND NOT has_table_privilege('authenticated', 'extensions.pg_stat_statements', 'SELECT')),
    'anon/authenticated must not read pg_stat_statements'::text;

  -- (جديد) سياسة profiles_update_own تحرس الحقول الحساسة في WITH CHECK
  RETURN QUERY SELECT 'profiles_update_guarded_with_check'::text,
    (SELECT count(*) = 1
       AND bool_and(with_check LIKE '%profile_guard_fields_unchanged%')
     FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_update_own'
       AND cmd = 'UPDATE'),
    'profiles_update_own must re-guard role/is_banned/referred_by in WITH CHECK'::text;

  -- (جديد) اشتقاق receipt_url خادمياً محميّ بتريجر على orders و wallet_topups
  RETURN QUERY SELECT 'receipt_url_derived_server_side'::text,
    ((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'orders'
         AND t.tgname = 'trg_derive_receipt_url_orders') = 1
     AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'wallet_topups'
         AND t.tgname = 'trg_derive_receipt_url_topups') = 1
     AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'payment_receipts'
         AND t.tgname = 'trg_validate_receipt_path') = 1),
    'receipt_url must be derived from payment_receipts.receipt_path via triggers'::text;

  -- (جديد) لا EXECUTE لـ anon/authenticated على دالة اختبار داخلية
  RETURN QUERY SELECT 'internal_test_fn_not_exposed'::text,
    (NOT has_function_privilege('anon', 'public.verify_privilege_model()', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.verify_privilege_model()', 'EXECUTE')),
    'verify_privilege_model must not be reachable from client roles'::text;

  -- (جديد) الكوبونات الجديدة 10 خانات على الأقل (تريجر قائم)
  RETURN QUERY SELECT 'coupon_code_strength_enforced'::text,
    ((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'coupons'
         AND t.tgname = 'trg_enforce_coupon_code_strength') = 1),
    'coupons must reject new codes shorter than 10 alphanumeric characters'::text;
END
$fn$;
REVOKE EXECUTE ON FUNCTION public.verify_privilege_model() FROM PUBLIC, anon, authenticated;

SELECT 'migration_2026-10-11_hardening_remaining_applied' AS status;
