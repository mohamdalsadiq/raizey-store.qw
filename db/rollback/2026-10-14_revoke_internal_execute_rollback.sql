-- ROLLBACK for db/migrations/2026-10-14_revoke_internal_execute.sql
--
-- Restores the pre-migration state: PostgreSQL's default PUBLIC EXECUTE on the
-- internal helpers, and the (unnecessarily broad) anon grant on the profile
-- guard used by the profiles_update_own policy.
begin;

do $$
declare
  r record;
  internal text[] := array[
    'apply_referral_signup_metadata', 'assert_wallet_ledger_entry', 'award_loyalty_points',
    'derive_receipt_url_from_receipt', 'enforce_coupon_code_strength', 'handle_new_user',
    'link_order_payment_code', 'protect_notification_fields', 'protect_order_fields',
    'protect_profile_columns', 'protect_profile_fields', 'protect_profile_insert',
    'protect_topup_insert', 'set_order_code', 'set_row_updated_at',
    'set_store_sections_updated_at', 'touch_subcategories_updated_at',
    'validate_receipt_path', 'verify_order_price_before_insert',
    'profile_guard_fields_unchanged'
  ];
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (internal)
  loop
    execute format('grant execute on function %s to public', r.sig);
  end loop;
end $$;

commit;
