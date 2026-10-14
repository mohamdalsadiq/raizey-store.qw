-- MEEM STORE — least privilege on internal routines (2026-10-14)
--
-- Why: PostgreSQL grants EXECUTE on every new function to PUBLIC by default, so
-- each trigger helper in `public` also became callable by anon/authenticated.
-- Trigger invocation does NOT check EXECUTE (the trigger machinery calls the
-- function internally), so client roles never need those grants. Revoking them
-- removes a needless callable surface without changing any behaviour.
--
-- The storefront's own read RPCs stay granted: get_banners_public() and
-- get_top_ordered_products() are the only two functions anon may execute.
--
-- Idempotent. ROLLBACK: db/rollback/2026-10-14_revoke_internal_execute_rollback.sql
begin;

do $$
declare
  r record;
  trigger_only text[] := array[
    'apply_referral_signup_metadata', 'assert_wallet_ledger_entry', 'award_loyalty_points',
    'derive_receipt_url_from_receipt', 'enforce_coupon_code_strength', 'handle_new_user',
    'link_order_payment_code', 'protect_notification_fields', 'protect_order_fields',
    'protect_profile_columns', 'protect_profile_fields', 'protect_profile_insert',
    'protect_topup_insert', 'set_order_code', 'set_row_updated_at',
    'set_store_sections_updated_at', 'touch_subcategories_updated_at',
    'validate_receipt_path', 'verify_order_price_before_insert'
  ];
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (trigger_only)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    -- service_role still resolves it if any server-side caller needs it
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;

  -- profile_guard_fields_unchanged is referenced by the profiles_update_own
  -- WITH CHECK, and policy expressions run as the *caller*, so authenticated
  -- must keep EXECUTE on it. anon has no business calling it at all.
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'profile_guard_fields_unchanged'
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end $$;

-- self-check: no client role may execute any of the internal helpers any more
-- (profile_guard_fields_unchanged is deliberately absent from trigger_only:
-- authenticated must keep it for the profiles_update_own WITH CHECK).
do $$
declare
  leaked text;
  trigger_only text[] := array[
    'apply_referral_signup_metadata', 'assert_wallet_ledger_entry', 'award_loyalty_points',
    'derive_receipt_url_from_receipt', 'enforce_coupon_code_strength', 'handle_new_user',
    'link_order_payment_code', 'protect_notification_fields', 'protect_order_fields',
    'protect_profile_columns', 'protect_profile_fields', 'protect_profile_insert',
    'protect_topup_insert', 'set_order_code', 'set_row_updated_at',
    'set_store_sections_updated_at', 'touch_subcategories_updated_at',
    'validate_receipt_path', 'verify_order_price_before_insert'
  ];
begin
  select string_agg(p.proname, ', ' order by p.proname) into leaked
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = any (trigger_only)
    and (has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if leaked is not null then
    raise exception 'client roles still hold EXECUTE on internal routines: %', leaked;
  end if;
end $$;

commit;
