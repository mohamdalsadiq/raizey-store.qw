-- ROLLBACK for db/migrations/2026-10-14_referral_code_check_for_anon.sql
-- Puts back the pre-migration state (registration with a referral code breaks
-- again — only run this if the enumeration trade-off is re-evaluated).
begin;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'validate_referral_short_code'
  ) then
    execute 'revoke execute on function public.validate_referral_short_code(text) from anon';
  end if;
end $$;

commit;
