-- MEEM STORE — registration can validate a referral code again (2026-10-14)
--
-- Bug this fixes (live): register.html validates the referral code *before*
-- sign-up, i.e. as `anon`, and the submit handler refuses to continue when the
-- check fails. anon had no EXECUTE grant on public.validate_referral_short_code,
-- so every code — valid or not — came back as an error and the page showed
-- "كود الإحالة غير موجود أو غير صالح" and blocked account creation.
--
-- Why granting it back is safe:
--   · the function returns RETURNS TABLE(valid boolean, reason text) — no name,
--     no email, no id: nothing but "this code exists / does not exist";
--   · the code space is now 'MEEM' + 8 chars from a 32-symbol alphabet
--     (2026-10-12_referral_prefix_meem.sql), i.e. ~1.1e12 codes, so the
--     enumeration oracle flagged as H4 in SECURITY-AUDIT-LIVE-2026-10-08.md is
--     no longer practical;
--   · it is STABLE + SECURITY DEFINER with `set search_path to 'public'`, and it
--     never writes.
-- The server still decides: the referral is applied from the sign-up metadata by
-- the handle_new_user/apply_referral_signup_metadata trigger, not by the client.
--
-- Idempotent. ROLLBACK: db/rollback/2026-10-14_referral_code_check_for_anon_rollback.sql
begin;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'validate_referral_short_code'
  ) then
    execute 'grant execute on function public.validate_referral_short_code(text) to anon';
  end if;
end $$;

-- self-check: anon really can call it now
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'validate_referral_short_code'
  ) and not has_function_privilege('anon', 'public.validate_referral_short_code(text)', 'EXECUTE') then
    raise exception 'anon still cannot execute validate_referral_short_code';
  end if;
end $$;

commit;
