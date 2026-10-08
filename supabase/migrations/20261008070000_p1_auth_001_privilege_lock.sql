-- P1-AUTH-001: privilege protection regression lock.
--
-- Background: is_admin() / is_super_admin() are the exclusive privilege gates
-- (both enforce the banned check). This migration:
--   1. Re-pins is_admin() byte-identical as canonical.
--   2. Adds verify_privilege_model() — a regression lock any future change can
--      run: it FAILS (passed=false) if anyone adds a permissive policy, a direct
--      anon grant, or weakens the admin gates.
--
-- SAFE: no behavior change. ROLLBACK: n/a.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$

  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND COALESCE(is_banned, false) = false
  );
$$;

COMMENT ON FUNCTION public.is_admin() IS
  'P1-AUTH-001 canonical privilege gate. Must enforce the banned check; single definition.';

CREATE OR REPLACE FUNCTION public.verify_privilege_model()
RETURNS TABLE(check_name text, passed boolean, details text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

COMMENT ON FUNCTION public.verify_privilege_model() IS
  'P1-AUTH-001 regression lock: run after any privilege/policy change; every row must pass.';
