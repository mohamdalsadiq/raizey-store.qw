-- ============================================================================
-- MEEM STORE — ROLLBACK لملف: db/migrations/2026-10-11_hardening_remaining.sql
-- File : db/rollback/2026-10-11_hardening_remaining.sql
-- Notes: يُعيد الكائنات إلى حالتها السابقة بالضبط. طبّقه في معاملة واحدة فقط
--        إذا فشل أي فحص بعد التطبيق أو لو طلبت الإدارة التراجع.
--        لا يمسّ أي صف بيانات زبون (باستثناء حذف مفتاح الإعداد الذي أضافه الملف).
-- ============================================================================

-- 1) إعادة منح pg_stat_statements كما كانت (مقابل إغلاق M1)
GRANT SELECT ON TABLE extensions.pg_stat_statements TO anon, authenticated;
DO $$
BEGIN
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION extensions.pg_stat_statements(boolean) TO PUBLIC'; EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION extensions.pg_stat_statements() TO PUBLIC'; EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION extensions.pg_stat_statements_info() TO PUBLIC'; EXCEPTION WHEN undefined_function THEN NULL; END;
END $$;

-- 2) إعادة صلاحيات الدوال الداخلية لأدوار العملاء (الحالة السابقة)
GRANT EXECUTE ON FUNCTION public.verify_privilege_model() TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_tx_ref(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_order_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_order_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_subcategories_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_row_updated_at() TO authenticated;

-- 3) إعادة الصلاحيات الافتراضية كما كانت (EXECUTE تلقائي لـauthenticated)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- 4) إعادة check_tx_ref_available إلى النسخة السابقة
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
 RETURNS TABLE(available boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                    DECLARE
                                                                                                                                                                                      v_user_id uuid := auth.uid();
                                                                                                                                                                                        v_norm text;
                                                                                                                                                                                        BEGIN
                                                                                                                                                                                          IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
                                                                                                                                                                                            v_norm := public.normalize_tx_ref(p_tx_ref);
                                                                                                                                                                                              IF v_norm IS NULL OR length(v_norm) < 6 THEN
                                                                                                                                                                                                  RETURN QUERY SELECT false, 'invalid_tx_ref';
                                                                                                                                                                                                      RETURN;
                                                                                                                                                                                                        END IF;
                                                                                                                                                                                                          IF EXISTS (SELECT 1 FROM public.payment_receipts WHERE tx_ref_norm = v_norm)
                                                                                                                                                                                                               OR EXISTS (SELECT 1 FROM public.orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm)
                                                                                                                                                                                                                    OR EXISTS (SELECT 1 FROM public.wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm) THEN
                                                                                                                                                                                                                        RETURN QUERY SELECT false, 'duplicate_transaction_ref';
                                                                                                                                                                                                                            RETURN;
                                                                                                                                                                                                                              END IF;
                                                                                                                                                                                                                                RETURN QUERY SELECT true, 'available';
                                                                                                                                                                                                                                END;
                                                                                                                                                                                                                                $function$

GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text) TO authenticated;

-- 5) إعادة validate_payment_code إلى النسخة السابقة
CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
 RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END
$function$

-- 6) إزالة تريجر طول الكوبون
DROP TRIGGER IF EXISTS trg_enforce_coupon_code_strength ON public.coupons;
DROP FUNCTION IF EXISTS public.enforce_coupon_code_strength();

-- 7) إعادة وصول anon إلى validate_referral_short_code
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(text) TO PUBLIC, anon;

-- 8) إعادة سياسة profiles_update_own إلى نسختها السابقة (بلا WITH CHECK مقارن)
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());
DROP FUNCTION IF EXISTS public.profile_guard_fields_unchanged(uuid,text,boolean,uuid,text,text,boolean,boolean,boolean,boolean,integer);

-- 9) إزالة تريجرات اشتقاق receipt_url والتحقق من المسار
DROP TRIGGER IF EXISTS trg_derive_receipt_url_orders ON public.orders;
DROP TRIGGER IF EXISTS trg_derive_receipt_url_topups ON public.wallet_topups;
DROP TRIGGER IF EXISTS trg_validate_receipt_path ON public.payment_receipts;
DROP FUNCTION IF EXISTS public.derive_receipt_url_from_receipt();
DROP FUNCTION IF EXISTS public.validate_receipt_path();

-- 10) حذف مفتاح الإعداد الذي أضافه الملف
DELETE FROM public.settings WHERE key = 'auto_accept_max_sdg';

-- 11) إعادة verify_privilege_model إلى النسخة السابقة (مكشوفة لـauthenticated كما كانت)
CREATE OR REPLACE FUNCTION public.verify_privilege_model()
 RETURNS TABLE(check_name text, passed boolean, details text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END;
$function$

GRANT EXECUTE ON FUNCTION public.verify_privilege_model() TO authenticated;

SELECT 'rollback_2026-10-11_hardening_remaining_applied' AS status;
